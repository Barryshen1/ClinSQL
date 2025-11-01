WITH
-- Admissions for female patients age 85-95
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 85 AND 95
),

-- Admissions that contain an asthma diagnosis (by d_icd_diagnoses.long_title containing 'asthma')
asthma_admissions AS (
  SELECT DISTINCT
    fa.*
  FROM
    female_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  USING (hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%asthma%'
),

-- All diagnosis rows (with descriptions) for admissions in the asthma cohort
admission_diagnoses AS (
  SELECT
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    LOWER(dd.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM asthma_admissions)
),

-- Compute comorbidity score and complication flags per admission
admission_metrics AS (
  SELECT
    ad.hadm_id,
    -- total non-asthma diagnosis rows (for info)
    SUM(CASE WHEN LOWER(ad.long_title) NOT LIKE '%asthma%' THEN 1 ELSE 0 END) AS total_diagnosis_rows,
    -- distinct non-asthma icd codes count = composite comorbidity score
    COUNT(DISTINCT CASE WHEN LOWER(ad.long_title) NOT LIKE '%asthma%' THEN ad.icd_code ELSE NULL END) AS comorbidity_score,
    -- cardiovascular complication flag: any dx with cardiovascular keywords
    MAX(
      CASE
        WHEN LOWER(ad.long_title) LIKE '%myocard%'
          OR LOWER(ad.long_title) LIKE '%heart failure%'
          OR LOWER(ad.long_title) LIKE '%congestive heart failure%'
          OR LOWER(ad.long_title) LIKE '%ischemic%'
          OR LOWER(ad.long_title) LIKE '%coronary%'
          OR LOWER(ad.long_title) LIKE '%angina%'
          OR LOWER(ad.long_title) LIKE '%arrhythmia%'
          OR LOWER(ad.long_title) LIKE '%cardiac arrest%'
          OR LOWER(ad.long_title) LIKE '%cardiac%'
          OR LOWER(ad.long_title) LIKE '%myocardial infarction%'
        THEN 1 ELSE 0
      END
    ) AS cardio_flag,
    -- neurologic complication flag: any dx with neurologic keywords
    MAX(
      CASE
        WHEN LOWER(ad.long_title) LIKE '%stroke%'
          OR LOWER(ad.long_title) LIKE '%cerebro%'
          OR LOWER(ad.long_title) LIKE '%transient ischemic attack%'
          OR LOWER(ad.long_title) LIKE '%tia%'
          OR LOWER(ad.long_title) LIKE '%seizure%'
          OR LOWER(ad.long_title) LIKE '%convulsion%'
          OR LOWER(ad.long_title) LIKE '%encephal%'
          OR LOWER(ad.long_title) LIKE '%intracerebral%'
          OR LOWER(ad.long_title) LIKE '%intracranial%'
          OR LOWER(ad.long_title) LIKE '%subarachnoid%'
          OR LOWER(ad.long_title) LIKE '%neurologic%'
        THEN 1 ELSE 0
      END
    ) AS neuro_flag
  FROM
    admission_diagnoses ad
  GROUP BY
    ad.hadm_id
),

-- Ensure all asthma_admissions are present, even if no diagnoses rows matched (unlikely)
admissions_with_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    COALESCE(am.comorbidity_score, 0) AS comorbidity_score,
    COALESCE(am.cardio_flag, 0) AS cardio_flag,
    COALESCE(am.neuro_flag, 0) AS neuro_flag
  FROM
    asthma_admissions a
  LEFT JOIN
    admission_metrics am
  USING (hadm_id)
),

-- Assign quartiles based on comorbidity_score (NTILE(4) -> approx equal-sized groups ordered by score)
admissions_quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY comorbidity_score ASC) AS comorbidity_quartile
  FROM
    admissions_with_metrics
)

-- Final aggregation: for each quartile report counts and rates
SELECT
  comorbidity_quartile AS quartile,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  SUM(cardio_flag) AS n_cardiovascular_complications,
  ROUND(100.0 * SUM(cardio_flag) / COUNT(*), 2) AS cardiovascular_complication_percent,
  SUM(neuro_flag) AS n_neurologic_complications,
  ROUND(100.0 * SUM(neuro_flag) / COUNT(*), 2) AS neurologic_complication_percent,
  -- median (approx) comorbidity score per quartile
  APPROX_QUANTILES(comorbidity_score, 2)[OFFSET(1)] AS median_comorbidity_score
FROM
  admissions_quartiled
GROUP BY
  comorbidity_quartile
ORDER BY
  comorbidity_quartile;