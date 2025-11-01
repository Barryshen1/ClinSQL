WITH qualifying_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 49 AND 59
    AND (
      LOWER(i.first_careunit) LIKE '%stepdown%'
      OR LOWER(i.first_careunit) LIKE '%intermediate%'
      OR LOWER(i.first_careunit) LIKE '%imc%'
      OR LOWER(i.last_careunit) LIKE '%stepdown%'
      OR LOWER(i.last_careunit) LIKE '%intermediate%'
      OR LOWER(i.last_careunit) LIKE '%imc%'
    )
),
dbp_means AS (
  SELECT qs.stay_id, AVG(ce.valuenum) AS mean_dbp
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = qs.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%diastolic%'
    AND (LOWER(di.label) LIKE '%blood pressure%' OR LOWER(di.label) LIKE '%bp%')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 10 AND 150
  GROUP BY qs.stay_id
  HAVING COUNT(ce.valuenum) >= 2
),
quantiles_cte AS (
  SELECT APPROX_QUANTILES(mean_dbp, 4) AS quantiles
  FROM dbp_means
)
SELECT
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM quantiles_cte;