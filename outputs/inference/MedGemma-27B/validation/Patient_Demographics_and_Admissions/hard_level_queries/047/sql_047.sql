WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag,
    d.long_title AS primary_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'ED'
    AND d.icd_code LIKE 'I6%' -- Hemorrhagic stroke codes start with I6
    AND d.icd_version = 10
), ReadmissionStatus AS (
  SELECT
    pc.subject_id,
    pc.admittime AS index_admittime,
    pc.dischtime AS index_dischtime,
    pc.deathtime AS index_deathtime,
    pc.hospital_expire_flag AS index_hospital_expire_flag,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = pc.subject_id
          AND a2.admittime > pc.dischtime
          AND a2.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
      ) THEN TRUE
      ELSE FALSE
    END AS readmitted_within_30_days
  FROM PatientCohort AS pc
), ReadmissionAnalysis AS (
  SELECT
    rs.subject_id,
    rs.readmitted_within_30_days,
    rs.index_dischtime,
    rs.index_admittime,
    rs.index_deathtime,
    rs.index_hospital_expire_flag
  FROM ReadmissionStatus AS rs
), ReadmissionRate AS (
  SELECT
    AVG(CASE WHEN readmitted_within_30_days THEN 1 ELSE 0 END) AS readmission_rate
  FROM ReadmissionAnalysis
), LOSAnalysis AS (
  SELECT
    subject_id,
    readmitted_within_30_days,
    index_dischtime,
    index_admittime,
    index_deathtime,
    index_hospital_expire_flag
  FROM ReadmissionAnalysis
), MedianLOS AS (
  SELECT
    readmitted_within_30_days,
    AVG(los) AS median_los
  FROM (
    SELECT
      readmitted_within_30_days,
      (TIMESTAMP_DIFF(index_dischtime, index_admittime, DAY) + 1) AS los
    FROM LOSAnalysis
  ) AS sub
  GROUP BY
    readmitted_within_30_days
), LOSDistribution AS (
  SELECT
    readmitted_within_30_days,
    AVG(CASE WHEN (TIMESTAMP_DIFF(index_dischtime, index_admittime, DAY) + 1) > 4 THEN 1 ELSE 0 END) AS pct_los_gt_4_days
  FROM LOSAnalysis
  GROUP BY
    readmitted_within_30_days
)
SELECT
  rr.readmission_rate,
  ml.median_los AS median_los_readmitted,
  ml2.median_los AS median_los_non_readmitted,
  ld.pct_los_gt_4_days AS pct_los_gt_4_days_readmitted,
  ld2.pct_los_gt_4_days AS pct_los_gt_4_days_non_readmitted
FROM ReadmissionRate AS rr
LEFT JOIN MedianLOS AS ml
  ON ml.readmitted;