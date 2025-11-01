WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

complications AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%'
              OR LOWER(dd.long_title) LIKE '%heart failure%'
              OR LOWER(dd.long_title) LIKE '%arrhythmia%' THEN 1 ELSE 0 END) AS cardio_complication,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%'
              OR LOWER(dd.long_title) LIKE '%seizure%' THEN 1 ELSE 0 END) AS neuro_complication
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%heart failure%'
    OR LOWER(dd.long_title) LIKE '%arrhythmia%'
    OR LOWER(dd.long_title) LIKE '%stroke%'
    OR LOWER(dd.long_title) LIKE '%seizure%'
  GROUP BY
    d.hadm_id
),

risk_score AS (
  SELECT
    pa.*,
    COALESCE(c.cardio_complication, 0) AS cardio_complication,
    COALESCE(c.neuro_complication, 0) AS neuro_complication,
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    CASE
      WHEN pa.deathtime IS NOT NULL AND pa.deathtime <= DATETIME_ADD(pa.admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS mortality_30d,
    NTILE(5) OVER (ORDER BY pa.anchor_age + pa.icu_flag DESC) AS risk_quintile
  FROM
    pneumonia_admissions pa
  LEFT JOIN
    complications c
    ON pa.hadm_id = c.hadm_id
)

SELECT
  risk_quintile,
  COUNT(*) AS patient_count,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(cardio_complication) AS cardio_complication_rate,
  AVG(neuro_complication) AS neuro_complication_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_survivors
FROM
  risk_score
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;