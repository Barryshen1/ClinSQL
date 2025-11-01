WITH patient_admissions AS (
  SELECT 
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'F'
),
filtered_admissions AS (
  SELECT *
  FROM patient_admissions
  WHERE 
    age_at_admission BETWEEN 64 AND 74
    AND los_days BETWEEN 1 AND 7
),
aki_diagnoses AS (
  SELECT 
    hadm_id,
    seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') 
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
aki_admissions AS (
  SELECT 
    fa.hadm_id,
    fa.los_days,
    MIN(aki.seq_num) AS min_aki_seq
  FROM filtered_admissions fa
  INNER JOIN aki_diagnoses aki
    ON fa.hadm_id = aki.hadm_id
  GROUP BY fa.hadm_id, fa.los_days
),
aki_with_type AS (
  SELECT 
    hadm_id,
    los_days,
    CASE 
      WHEN min_aki_seq = 1 THEN 'primary'
      ELSE 'secondary'
    END AS aki_type
  FROM aki_admissions
),
radiology_events AS (
  SELECT DISTINCT
    hc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON CAST(hc.hcpcs_cd AS STRING) = d.code
  WHERE d.category = 'Radiology'
),
imaging_counts AS (
  SELECT 
    aki.hadm_id,
    COUNT(rad.hadm_id) AS imaging_count
  FROM aki_with_type aki
  LEFT JOIN radiology_events rad
    ON aki.hadm_id = rad.hadm_id
  GROUP BY aki.hadm_id
),
base AS (
  SELECT 
    aki.hadm_id,
    aki.los_days,
    aki.aki_type,
    CASE 
      WHEN aki.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN aki.los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    COALESCE(img.imaging_count, 0) AS imaging_count
  FROM aki_with_type aki
  LEFT JOIN imaging_counts img
    ON aki.hadm_id = img.hadm_id
),
quartiles AS (
  SELECT 
    los_group,
    aki_type,
    APPROX_QUANTILES(imaging_count, 4) AS quartiles_arr
  FROM base
  GROUP BY los_group, aki_type
)
SELECT 
  los_group,
  aki_type,
  quartiles_arr[OFFSET(1)] AS q1,
  quartiles_arr[OFFSET(2)] AS median,
  quartiles_arr[OFFSET(3)] AS q3
FROM quartiles
ORDER BY los_group, aki_type;