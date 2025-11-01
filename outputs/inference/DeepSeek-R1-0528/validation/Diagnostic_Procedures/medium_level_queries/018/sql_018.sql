WITH hemorrhagic_stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(430|431|432)')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^(I60|I61|I62)'))
),
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN hemorrhagic_stroke_codes hsc
    ON diag.icd_code = hsc.icd_code AND diag.icd_version = hsc.icd_version
  WHERE p.gender = 'F'
),
cohort_with_age AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_adm
  FROM cohort
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 80 AND 90
),
icu_los_per_admission AS (
  SELECT 
    hadm_id,
    SUM(los) AS total_icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
  HAVING SUM(los) BETWEEN 1 AND 7
),
ultrasound_counts AS (
  SELECT
    c.hadm_id,
    c.total_icu_los,
    COUNTIF(dh.code IS NOT NULL) AS ultrasound_count
  FROM (
    SELECT 
      cwa.hadm_id,
      cwa.admittime,
      cwa.dischtime,
      icu.total_icu_los
    FROM cohort_with_age cwa
    INNER JOIN icu_los_per_admission icu
      ON cwa.hadm_id = icu.hadm_id
  ) c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
    ON c.hadm_id = hcpc.hadm_id
    AND hcpc.chartdate BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON hcpc.hcpcs_cd = dh.code
    AND (LOWER(dh.long_description) LIKE '%ultrasound%' OR LOWER(dh.short_description) LIKE '%ultrasound%')
  GROUP BY c.hadm_id, c.total_icu_los
)
SELECT
  CASE
    WHEN total_icu_los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN total_icu_los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS icu_stay_group,
  COUNT(hadm_id) AS num_admissions,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM ultrasound_counts
GROUP BY icu_stay_group;