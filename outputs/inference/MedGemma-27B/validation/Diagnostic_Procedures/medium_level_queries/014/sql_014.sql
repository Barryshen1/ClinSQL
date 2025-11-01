WITH PatientACS AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND d.icd_code IN ('410', '411', '412', '413', '414', '420', '421', '422', '427', '428', '429') -- ACS ICD-10 codes
),
AdmissionACS AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientACS AS pa
    ON a.subject_id = pa.subject_id
),
UltrasoundCounts AS (
  SELECT
    a.hadm_id,
    COUNT(hc.hcpcs_cd) AS ultrasound_count
  FROM AdmissionACS AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON a.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd LIKE '76%' -- HCPCS codes starting with 76 are typically ultrasounds
  GROUP BY
    a.hadm_id
),
StayDuration AS (
  SELECT
    a.hadm_id,
    -- Calculate stay duration in days
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1) AS stay_duration_days
  FROM AdmissionACS AS a
),
DiagnosisType AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM AdmissionACS AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
)
SELECT
  ud.hadm_id,
  ud.ultrasound_count,
  sd.stay_duration_days,
  dt.diagnosis_type,
  AVG(ud.ultrasound_count) OVER (PARTITION BY sd.stay_duration_days, dt.diagnosis_type) AS mean_ultrasounds,
  MIN(ud.ultrasound_count) OVER (PARTITION BY sd.stay_duration_days, dt.diagnosis_type) AS min_ultrasounds,
  MAX(ud.ultrasound_count) OVER (PARTITION BY sd.stay_duration_days, dt.diagnosis_type) AS max_ultrasounds
FROM UltrasoundCounts AS ud
JOIN StayDuration AS sd
  ON ud.hadm_id = sd.hadm_id
JOIN DiagnosisType AS dt
  ON ud.hadm_id = dt.hadm_id
WHERE
  sd.stay_duration_days BETWEEN 1 AND 7
GROUP BY
  ud.hadm_id,
  ud.ultrasound_count,
  sd.stay_duration_days,
  dt.diagnosis_type
ORDER BY
  sd.stay_duration_days,
  dt.diagnosis_type;