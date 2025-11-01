WITH base_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
),

postop_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%postoperative%'
     OR LOWER(ddi.long_title) LIKE '%postop%'
),

comorbidity_counts AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  WHERE NOT (LOWER(ddi.long_title) LIKE '%postoperative%'
              OR LOWER(ddi.long_title) LIKE '%postop%')
  GROUP BY di.hadm_id
),

icu_flag AS (
  SELECT DISTINCT
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)

SELECT
  CASE WHEN icu_flag.icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE WHEN hospital_los_days <= 5 THEN '≤5' ELSE '>5' END AS los_bin,
  CASE
    WHEN c.comorb_count <= 1 THEN '0-1'
    WHEN c.comorb_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_bin,
  COUNT(*) AS N,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS mortality_percent,
  ROUND(AVG(c.comorb_count), 2) AS avg_comorbidity_count
FROM (
  SELECT
    bc.*,
    TIMESTAMP_DIFF(bc.dischtime, bc.admittime, HOUR)/24.0 AS hospital_los_days
  FROM base_cohort bc
  JOIN postop_hadm ph
    ON bc.hadm_id = ph.hadm_id
) adm
LEFT JOIN comorbidity_counts c
  ON adm.hadm_id = c.hadm_id
LEFT JOIN icu_flag
  ON adm.hadm_id = icu_flag.hadm_id
GROUP BY
  icu_status, los_bin, comorbidity_bin
ORDER BY
  icu_status, los_bin, comorbidity_bin;