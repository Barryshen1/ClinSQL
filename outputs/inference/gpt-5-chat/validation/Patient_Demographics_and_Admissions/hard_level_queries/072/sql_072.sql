WITH principal_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),

index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.gender,
    p.anchor_age,
    a.insurance,
    a.admission_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN principal_dx pd
    ON a.subject_id = pd.subject_id AND a.hadm_id = pd.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND UPPER(a.admission_location) = 'SKILLED NURSING FACILITY'
),

readmission_flag AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    idx.admittime,
    idx.dischtime,
    idx.los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = idx.subject_id
        AND a2.admittime > idx.dischtime
        AND a2.admittime <= DATETIME_ADD(idx.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM index_admissions idx
)

SELECT
  readmitted,
  -- median LOS
  APPROX_QUANTILES(los, 3)[OFFSET(1)] AS median_los,
  -- percent LOS > 8 days
  100 * SUM(CASE WHEN los > 8 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt_8d,
  COUNT(*) AS n_index_admissions
FROM readmission_flag
GROUP BY readmitted
ORDER BY readmitted DESC;