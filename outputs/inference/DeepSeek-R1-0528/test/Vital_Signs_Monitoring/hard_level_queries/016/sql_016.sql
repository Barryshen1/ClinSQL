WITH transplant_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE 'V42%') OR
    (icd_version = 10 AND icd_code LIKE 'Z94%')
),
transplant_patients AS (
  SELECT DISTINCT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN transplant_codes 
    ON diag.icd_code = transplant_codes.icd_code 
    AND diag.icd_version = transplant_codes.icd_version
),
base_cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime, 
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM adm.admittime) AS adm_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit,
    ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM base_cohort
  WHERE 
    age_admit BETWEEN 57 AND 67
    AND stay_num = 1
),
cohort_with_transplant AS (
  SELECT 
    f.*,
    CASE WHEN t.subject_id IS NOT NULL THEN 1 ELSE 0 END AS transplant_status
  FROM filtered_cohort f
  LEFT JOIN transplant_patients t
    ON f.subject_id = t.subject_id
),
events AS (
  SELECT 
    ce.stay_id,
    COUNTIF(
      (ce.itemid IN (223760, 223761, 223762, 223763) AND 
        ((ce.itemid IN (223760, 223763) AND (ce.valuenum - 32) * 5/9 > 38.5) OR 
         (ce.itemid IN (223761, 223762) AND ce.valuenum > 38.5))
      ) OR 
      (ce.itemid = 220277 AND ce.valuenum < 90) OR 
      (ce.itemid IN (220210, 224690) AND ce.valuenum > 20)
    ) AS composite_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_with_transplant c
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
final_data AS (
  SELECT 
    c.stay_id,
    c.transplant_status,
    COALESCE(e.composite_score, 0) AS composite_score,
    c.los,
    c.hospital_expire_flag AS mortality
  FROM cohort_with_transplant c
  LEFT JOIN events e
    ON c.stay_id = e.stay_id
),
per_group AS (
  SELECT 
    transplant_status,
    APPROX_QUANTILES(composite_score, 100) AS composite_arr,
    APPROX_QUANTILES(los, 100) AS los_arr,
    APPROX_QUANTILES(mortality, 100) AS mortality_arr,
    AVG(mortality) * 100 AS mortality_rate_percent,
    COUNT(*) AS n
  FROM final_data
  GROUP BY transplant_status
)
SELECT 
  transplant_status,
  composite_arr[OFFSET(25)] AS p25_composite,
  composite_arr[OFFSET(50)] AS median_composite,
  composite_arr[OFFSET(75)] AS p75_composite,
  los_arr[OFFSET(25)] AS p25_los,
  los_arr[OFFSET(50)] AS median_los,
  los_arr[OFFSET(75)] AS p75_los,
  mortality_arr[OFFSET(25)] AS p25_mortality,
  mortality_arr[OFFSET(50)] AS median_mortality,
  mortality_arr[OFFSET(75)] AS p75_mortality,
  mortality_rate_percent,
  n
FROM per_group
ORDER BY transplant_status;