WITH cellulitis_icd AS (
  -- ICD-9: 682.x, ICD-10: L03.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^682')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^L03'))
),
index_admissions AS (
  -- Female Medicare patients aged 55-65, admitted from ED, principal cellulitis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender,
    adm.insurance,
    adm.admission_location,
    adm.admission_type,
    adm.race,
    adm.marital_status,
    adm.language,
    -- LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN cellulitis_icd icd
    ON dx.icd_code = icd.icd_code AND dx.icd_version = icd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND adm.insurance = 'Medicare'
    AND (
      LOWER(adm.admission_location) LIKE '%emergency%'
      OR LOWER(adm.admission_location) LIKE '%ed%'
    )
    AND dx.seq_num = 1 -- principal diagnosis
    AND adm.hospital_expire_flag = 0 -- exclude deaths during index stay
    AND adm.deathtime IS NULL -- extra safety
),
readmissions AS (
  -- For each index admission, find first readmission within 30 days
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.dischtime AS index_dischtime,
    MIN(next.admittime) AS readmit_admittime,
    MIN(next.hadm_id) AS readmit_hadm_id
  FROM index_admissions idx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON idx.subject_id = next.subject_id
    AND next.admittime > idx.dischtime
    AND DATETIME_DIFF(next.admittime, idx.dischtime, DAY) <= 30
  GROUP BY idx.subject_id, idx.hadm_id, idx.dischtime
),
index_with_readmit_flag AS (
  -- Mark index admissions as readmitted or not
  SELECT
    idx.*,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS was_readmitted
  FROM index_admissions idx
  LEFT JOIN readmissions r
    ON idx.subject_id = r.subject_id
    AND idx.hadm_id = r.index_hadm_id
)
SELECT
  -- 30-day readmission rate
  ROUND(100 * SUM(was_readmitted) / COUNT(*), 2) AS readmission_rate_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(was_readmitted = 1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(was_readmitted = 0, los, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  -- Percent of index admissions with LOS > 7 days
  ROUND(100 * COUNTIF(los > 7) / COUNT(*), 2) AS percent_los_gt_7_days,
  -- Percent of index admissions with LOS > 7 days, by readmission status
  ROUND(100 * COUNTIF(los > 7 AND was_readmitted = 1) / NULLIF(COUNTIF(was_readmitted = 1),0), 2) AS percent_los_gt_7_days_readmitted,
  ROUND(100 * COUNTIF(los > 7 AND was_readmitted = 0) / NULLIF(COUNTIF(was_readmitted = 0),0), 2) AS percent_los_gt_7_days_nonreadmitted,
  COUNT(*) AS n_index_admissions,
  SUM(was_readmitted) AS n_readmitted
FROM index_with_readmit_flag;