WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.admission_type,
    a.admission_location,
    d.long_title AS diagnosis_title,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND di.icd_code LIKE 'S72%' -- Femoral neck fracture codes
),
IndexStayLOS AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate LOS in days
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS index_los
  FROM PatientCohort
),
ReadmissionStatus AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime AS index_admittime,
    pc.dischtime AS index_dischtime,
    -- Check for readmission within 30 days
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = pc.subject_id
          AND a2.admittime > pc.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(pc.dischtime, INTERVAL 30 DAY)
      ) THEN TRUE
      ELSE FALSE
    END AS is_readmitted
  FROM PatientCohort AS pc
),
CombinedData AS (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.index_admittime,
    rs.index_dischtime,
    rs.is_readmitted,
    isl.index_los
  FROM ReadmissionStatus AS rs
  JOIN IndexStayLOS AS isl
    ON rs.subject_id = isl.subject_id AND rs.hadm_id = isl.hadm_id
)
SELECT
  COUNT(CASE WHEN is_readmitted = TRUE THEN 1 END) * 100.0 / COUNT(*) AS readmission_rate_30_day,
  MEDIAN(CASE WHEN is_readmitted = TRUE THEN index_los ELSE NULL END) AS median_los_readmitted,
  MEDIAN(CASE WHEN is_readmitted = FALSE THEN index_los ELSE NULL END) AS median_los_not_readmitted,
  COUNT(CASE WHEN index_los > 8 THEN 1 END) * 100.0 / COUNT(*) AS percent_initial_stays_gt_8_days
FROM CombinedData;