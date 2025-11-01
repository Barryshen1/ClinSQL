WITH eligible_stays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND unitname IN ('Cel', 'C')
),

stay_temps AS (
  SELECT
    es.subject_id,
    es.hadm_id,
    es.stay_id,
    AVG(ce.valuenum) AS mean_temp
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON es.subject_id = ce.subject_id
     AND es.hadm_id    = ce.hadm_id
     AND es.stay_id    = ce.stay_id
    JOIN temp_items ti
      ON ce.itemid = ti.itemid
  WHERE
    ce.charttime BETWEEN es.intime
                     AND es.intime + INTERVAL 24 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY
    es.subject_id,
    es.hadm_id,
    es.stay_id
),

mi_flags AS (
  SELECT
    es.subject_id,
    es.hadm_id,
    MAX(
      CASE
        WHEN di.icd_version = 9
             AND di.icd_code LIKE '410%' THEN 1
        WHEN di.icd_version = 10
             AND LOWER(dg.long_title) LIKE '%myocardial infarction%' THEN 1
        ELSE 0
      END
    ) AS mi_flag
  FROM
    eligible_stays es
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON es.subject_id = di.subject_id
     AND es.hadm_id    = di.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dg
      ON di.icd_code    = dg.icd_code
     AND di.icd_version = dg.icd_version
  GROUP BY
    es.subject_id,
    es.hadm_id
),

classified AS (
  SELECT
    st.stay_id,
    st.mean_temp,
    mf.mi_flag,
    CASE
      WHEN st.mean_temp < 36.0 THEN '<36.0'
      WHEN st.mean_temp < 38.0 THEN '36.0–37.9'
      ELSE '>=38.0'
    END AS temp_category
  FROM
    stay_temps st
    LEFT JOIN mi_flags mf
      ON st.subject_id = mf.subject_id
     AND st.hadm_id    = mf.hadm_id
)

SELECT
  temp_category,
  COUNT(*)                                    AS N,
  ROUND(AVG(mean_temp), 2)                    AS mean_of_means,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(2)], 2) AS median,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(1)], 2) AS q1,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(3)], 2) AS q3,
  ROUND(100.0 * SUM(mi_flag) / COUNT(*), 1)     AS mi_rate_pct
FROM
  classified
GROUP BY
  temp_category
ORDER BY
  CASE temp_category
    WHEN '<36.0'     THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '>=38.0'    THEN 3
  END;