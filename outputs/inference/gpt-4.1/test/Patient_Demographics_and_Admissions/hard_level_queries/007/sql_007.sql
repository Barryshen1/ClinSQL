WITH tia_icd_codes AS (
  -- Get all ICD codes for TIA (ICD-9: 435.*, ICD-10: G45.*)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '435%')
     OR (icd_version = 10 AND icd_code LIKE 'G45%')
),
index_admissions AS (
  -- Select index admissions meeting all criteria
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.insurance,
    adm.admission_location,
    pat.anchor_age,
    pat.gender,
    diag.icd_code,
    diag.icd_version,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN tia_icd_codes ticd
    ON diag.icd_code = ticd.icd_code AND diag.icd_version = ticd.icd_version
  WHERE
    diag.seq_num = 1
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND LOWER(adm.insurance) LIKE '%medicare%'
    AND LOWER(adm.admission_location) LIKE '%emergency%'
    AND adm.dischtime IS NOT NULL
    AND adm.hospital_expire_flag = 0
),
readmissions AS (
  -- For each index admission, find if a readmission occurred within 30 days
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.admittime AS index_admittime,
    idx.dischtime AS index_dischtime,
    MIN(next.admittime) AS next_admittime,
    MIN(next.hadm_id) AS next_hadm_id,
    CASE
      WHEN MIN(next.admittime) IS NOT NULL
           AND TIMESTAMP_DIFF(MIN(next.admittime), idx.dischtime, DAY) BETWEEN 0 AND 30
        THEN 1
      ELSE 0
    END AS readmitted_within_30d,
    idx.los
  FROM index_admissions idx
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON idx.subject_id = next.subject_id
    AND next.admittime > idx.dischtime
    AND next.hadm_id != idx.hadm_id
    AND next.admittime <= TIMESTAMP_ADD(idx.dischtime, INTERVAL 30 DAY)
  GROUP BY idx.subject_id, idx.hadm_id, idx.admittime, idx.dischtime, idx.los
),
summary AS (
  SELECT
    COUNT(*) AS n_index_admissions,
    SUM(readmitted_within_30d) AS n_readmitted,
    SAFE_DIVIDE(SUM(readmitted_within_30d), COUNT(*)) AS readmission_rate,
    SAFE_DIVIDE(SUM(CASE WHEN los > 10 THEN 1 ELSE 0 END), COUNT(*)) AS pct_los_gt_10d
  FROM readmissions
),
median_los_readmitted AS (
  SELECT
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_readmitted
  FROM readmissions
  WHERE readmitted_within_30d = 1
),
median_los_not_readmitted AS (
  SELECT
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_not_readmitted
  FROM readmissions
  WHERE readmitted_within_30d = 0
)
SELECT
  s.readmission_rate,
  mr.median_los_readmitted,
  mn.median_los_not_readmitted,
  s.pct_los_gt_10d
FROM summary s
CROSS JOIN median_los_readmitted mr
CROSS JOIN median_los_not_readmitted mn
;