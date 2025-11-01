WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Check for readmission within 30 days using EXISTS
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` readm 
      WHERE a.subject_id = readm.subject_id
        AND readm.admittime > a.dischtime
        AND readm.admittime <= DATETIME_ADD(a.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmission_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.insurance = 'Medicare'
    AND di.seq_num = 1  -- Principal diagnosis
    AND ( -- Femoral neck fracture codes
      (di.icd_version = 9 AND di.icd_code IN ('82000', '82001', '82002', '82003', '82009', '8208', '8209'))
      OR
      (di.icd_version = 10 AND di.icd_code IN ('S7200', 'S7201', 'S7202', 'S7203', 'S7204', 'S7205', 'S7206', 'S7209'))
    )
    -- Age 58-68 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
)

SELECT
  COUNT(*) AS total_index_admissions,
  AVG(readmission_flag) * 100 AS readmission_rate_percent,
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM index_admissions WHERE readmission_flag = 1) AS median_los_readmitted,
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM index_admissions WHERE readmission_flag = 0) AS median_los_non_readmitted,
  AVG(CASE WHEN los > 8 THEN 1 ELSE 0 END) * 100 AS percent_initial_stays_gt_8_days
FROM index_admissions;