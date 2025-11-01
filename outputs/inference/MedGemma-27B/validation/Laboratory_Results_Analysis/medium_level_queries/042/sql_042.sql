WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 84 AND 94
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE 'I20%' -- Chest pain ICD-10 code
    AND d.seq_num = 1 -- First diagnosis
), TroponinInfo AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
), FirstTroponin AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    MIN(t.charttime) AS first_troponin_time,
    -- Use MAX(t.valuenum) to get the value corresponding to the MIN(t.charttime)
    MAX(t.valuenum) AS troponin_value,
    -- Use MAX(t.valueuom) to get the unit corresponding to the MIN(t.charttime)
    MAX(t.valueuom) AS troponin_uom
  FROM
    TroponinInfo AS t
  GROUP BY
    t.subject_id,
    t.hadm_id
), TroponinCategory AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    CASE
      WHEN ft.troponin_value < 0.01 THEN 'Normal'
      WHEN ft.troponin_value BETWEEN 0.01 AND 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    FirstTroponin AS ft
)
SELECT
  tc.troponin_category,
  COUNT(DISTINCT tc.subject_id) AS patient_count,
  COUNT(DISTINCT tc.subject_id) * 100.0 / COUNT(DISTINCT tc.subject_id) AS percentage,
  SUM(CASE WHEN ai.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  SUM(CASE WHEN ai.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT tc.subject_id) AS mortality_percentage
FROM
  TroponinCategory AS tc
INNER JOIN
  AdmissionInfo AS ai
  ON tc.subject_id = ai.subject_id AND tc.hadm_id = ai.hadm_id
INNER JOIN
  DiagnosisInfo AS di
  ON tc.subject_id = di.subject_id AND tc.hadm_id = di.hadm_id
GROUP BY
  tc.troponin_category
ORDER BY
  tc.troponin_category;