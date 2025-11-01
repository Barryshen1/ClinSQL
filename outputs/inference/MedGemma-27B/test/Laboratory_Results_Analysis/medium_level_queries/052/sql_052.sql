WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 81
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.insurance = 'Medicare'
    AND a.language = 'ENGL'
    AND a.marital_status = 'MARRIED'
    AND a.race = 'WHITE'
    AND a.hospital_expire_flag = 0
),
DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN AdmissionInfo AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    di.long_title LIKE '%myocardial infarction%'
    AND d.seq_num = 1
),
TroponinInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    l.valueuom AS troponin_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  JOIN DiagnosisInfo AS di
    ON l.subject_id = di.subject_id AND l.hadm_id = di.hadm_id
  WHERE
    d.label = 'Troponin I'
    AND l.charttime BETWEEN di.admittime AND di.dischtime
)
SELECT
  CASE
    WHEN troponin_value <= 0.04
    THEN 'Normal'
    WHEN troponin_value > 0.04 AND troponin_value <= 0.40
    THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
  AVG(troponin_value) AS mean,
  MEDIAN(troponin_value) AS median,
  PERCENTILE_CONT(troponin_value, 0.25) AS iqr_25,
  PERCENTILE_CONT(troponin_value, 0.75) AS iqr_75
FROM TroponinInfo
GROUP BY
  troponin_category
ORDER BY
  CASE
    WHEN troponin_category = 'Normal'
    THEN 1
    WHEN troponin_category = 'Borderline'
    THEN 2
    ELSE 3
  END;