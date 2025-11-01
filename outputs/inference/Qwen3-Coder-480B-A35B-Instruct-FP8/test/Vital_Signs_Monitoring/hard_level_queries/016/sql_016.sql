WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality,
    CASE WHEN tx.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_transplant
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.icd_code LIKE 'Z94%'
  ) tx
    ON icu.hadm_id = tx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 57 AND 67
),

-- Identify relevant itemids for vital signs
vitals AS (
  SELECT
    itemid,
    label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label IN ('SpO2', 'Respiratory Rate', 'Temperature Celsius', 'Temperature Fahrenheit')
),

-- Chartevents within first 72 hours
instability_events AS (
  SELECT
    c.stay_id,
    COUNT(*) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    vitals v ON c.itemid = v.itemid
  JOIN
    cohort coh ON c.stay_id = coh.stay_id
  WHERE
    c.charttime >= coh.intime
    AND c.charttime <= DATETIME_ADD(coh.intime, INTERVAL 72 HOUR)
    AND (
      (v.label = 'Temperature Celsius' AND c.valuenum > 38.5)
      OR (v.label = 'Temperature Fahrenheit' AND c.valuenum > 101.3)
      OR (v.label = 'SpO2' AND c.valuenum < 90)
      OR (v.label = 'Respiratory Rate' AND c.valuenum > 20)
    )
  GROUP BY
    c.stay_id
),

-- Final cohort with instability score
final_cohort AS (
  SELECT
    coh.*,
    COALESCE(ie.instability_score, 0) AS instability_score
  FROM
    cohort coh
  LEFT JOIN
    instability_events ie
    ON coh.stay_id = ie.stay_id
)

SELECT
  is_transplant,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability_score,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS median_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS p25_icu_los,
  APPROX_QUANTILES(icu_los, 100)[OFFSET(75)] AS p75_icu_los,
  AVG(mortality) AS mortality_rate
FROM
  final_cohort
GROUP BY
  is_transplant
ORDER BY
  is_transplant;