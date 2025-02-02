#' @title nowcasting_age
#'
#' @description Nowcasting estimation by age strcuture data, wrraper to a 'INLA' model
#'
#' @param dataset data pre formatted in to age classes and delays by week for each cases, delay triangle format
#'
#' @return Trajectories from the inner 'INLA' model
#' @export
nowcasting_age <- function(dataset){

  index.missing <- which(is.na(dataset$Y))

  dataset <- dataset |>
    dplyr::mutate(
      fx_etaria.num = as.numeric(fx_etaria))

  ## Model equation: intercept + age + f(time random effect | age) + f(Delay random effect | age)
  ## Y(t,Age) ~ 1 + Age + rw2(t,Age) + rw1(delay, Age),
  ## prec(rw2) ~ logGamma(10e-3, 10e-3), prec(rw1) ~ logGamma(10e-3, 10e-3)
  model <- Y ~ 1 + fx_etaria +
    f(Time,
      model = "rw2",
      hyper = list("prec" = list(prior = "loggamma",
                                 param = c(0.001, 0.001))
      ),
      group = fx_etaria.num, control.group = list(model = "iid")) +
    f(delay, model = "rw1",
      hyper = list("prec" = list(prior = "loggamma",
                                 param = c(0.001, 0.001))),
      group = fx_etaria.num, control.group = list(model = "iid")
    )

  ## Running the Negative Binomial model in INLA
  output0 <- INLA::inla(model, family = "nbinomial",
                        data = dataset,
                        control.predictor = list(link = 1, compute = T),
                        control.compute = list( config = T, waic=F, dic=F),
                        control.family = list(
                          hyper = list("theta" = list(prior = "loggamma",
                                                      param = c(0.001, 0.001))
                          )
                        )
  )

  ## Algorithm to get samples for the predictive distribution for the number of cases

  ## Step 1: Sampling from the approximate posterior distribution using INLA
  srag.samples0.list <- INLA::inla.posterior.sample(n = 1000, output0)

  ## Give a parameter to trajectories, TO-DO

  ## Step 2: Sampling the missing triangle from the likelihood using INLA estimates
  vector.samples0 <- lapply(X = srag.samples0.list,
                            FUN = function(x, idx = index.missing){
                              unif.log = 1
                              stats::rnbinom(n = idx,
                                             mu = exp(x$latent[idx]),
                                             size = x$hyperpar[1]
                              ) * unif.log
                            } )

  ## Step 3: Calculate N_{a,t} for each triangle sample {N_{t,a} : t=Tactual-Dmax+1,...Tactual}

  gg.age <- function(x, dados, idx){
    data.aux <- dados
    Tmin <- min(dados$Time[idx])
    data.aux$Y[idx] <- x
    data.aggregated <- data.aux |>
      ## Selecionando apenas os dias faltantes a partir
      ## do domingo da respectiva ultima epiweek
      ## com dados faltantes
      dplyr::filter(Time >= Tmin  ) |>
      dplyr::group_by(Time, dt_event, fx_etaria, fx_etaria.num) |>
      dplyr::summarise(
        Y = sum(Y), .groups = "keep"
      )
    data.aggregated
  }

  ## Step 4: Applying the age aggregation on each posterior
  tibble.samples.0 <- lapply( X = vector.samples0,
                              FUN = gg.age,
                              dados = dataset,
                              idx = index.missing)

  srag.pred.0 <- dplyr::bind_rows(tibble.samples.0, .id = "sample")

  ## Returning nowcasting estimation
  return(srag.pred.0)

}
