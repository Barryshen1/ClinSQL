WITH lower_gi_bleed_icds AS (
  -- Identify ICD codes for lower GI bleeding
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    LOWER(long_title) LIKE '%lower gi bleed%'
    OR LOWER(long_title) LIKE '%rectal bleed%'
    OR LOWER(long_title) LIKE '%melena%'
    OR LOWER(long_title) LIKE '%hematochezia%'
    OR (LOWER(long_title) LIKE '%gastrointestinal hemorrhage%' AND (LOWER(long_title) LIKE '%colon%' OR LOWER(long_title) LIKE '%rectum%' OR LOWER(long_title) LIKE '%anus%'))
    OR (LOWER(long_title) LIKE '%hemorrhage%' AND (LOWER(long_title) LIKE '%colon%' OR LOWER(long_title) LIKE '%rectum%' OR LOWER(long_title) LIKE '%anus%'))
),
index_admissions AS (
  -- Select qualifying index admissions
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.insurance,
    adm.admission_location,
    pat.gender,
    pat.anchor_age,
    pat.dod,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN lower_gi_bleed_icds icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    diag.seq_num = 1 -- principal diagnosis
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND adm.insurance = 'Medicare'
    AND (
      LOWER(adm.admission_location) LIKE '%emergency%'
      OR LOWER(adm.admission_type) = 'emergency'
    )
    AND adm.dischtime IS NOT NULL
    AND adm.admittime IS NOT NULL
),
alive_30d AS (
  -- Exclude patients who died in hospital or within 30 days of discharge
  SELECT
    ia.*
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ia.subject_id = pat.subject_id
  WHERE
    ia.hospital_expire_flag = 0
    AND (
      pat.dod IS NULL
      OR TIMESTAMP_DIFF(pat.dod, ia.dischtime, DAY) > 30
    )
),
readmissions AS (
  -- Find 30-day readmissions for each index admission
  SELECT
    a.subject_id,
    a.hadm_id AS index_hadm_id,
    a.dischtime AS index_dischtime,
    MIN(ra.admittime) AS readmit_admittime,
    MIN(ra.hadm_id) AS readmit_hadm_id
  FROM alive_30d a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON a.subject_id = ra.subject_id
    AND ra.admittime > a.dischtime
    AND TIMESTAMP_DIFF(ra.admittime, a.dischtime, DAY) <= 30
  GROUP BY a.subject_id, a.hadm_id, a.dischtime
),
final_cohort AS (
  -- Merge readmission info with index admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM alive_30d a
  LEFT JOIN readmissions r
    ON a.subject_id = r.subject_id AND a.hadm_id = r.index_hadm_id
)
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(SUM(readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  -- Median LOS for readmitted and not readmitted
  APPROX_QUANTILES(IF(readmitted = 1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted = 0, los, NULL), 2)[OFFSET(1)] AS median_los_not_readmitted,
  -- Percent with LOS > 6 days
  ROUND(SUM(CASE WHEN readmitted = 1 AND los > 6 THEN 1 ELSE 0 END) / NULLIF(SUM(readmitted),0) * 100, 2) AS percent_los_gt6_readmitted,
  ROUND(SUM(CASE WHEN readmitted = 0 AND los > 6 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN readmitted = 0 THEN 1 ELSE 0 END),0) * 100, 2) AS percent_los_gt6_not_readmitted
FROM final_cohort;