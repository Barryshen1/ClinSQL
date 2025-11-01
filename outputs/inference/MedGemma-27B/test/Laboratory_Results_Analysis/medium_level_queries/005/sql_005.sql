WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 40
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
),
DiagnosisInfo AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (
      d.long_title LIKE '%chest pain%' OR d.long_title LIKE '%myocardial infarction%'
    )
    AND di.seq_num = 1
),
TroponinInfo AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T, high sensitivity'
),
TroponinCategory AS (
  SELECT
    ti.subject_id,
    ti.hadm_id,
    ti.charttime,
    ti.troponin_value,
    ti.troponin_uom,
    CASE
      WHEN ti.troponin_value < 14
      THEN 'Normal'
      WHEN ti.troponin_value BETWEEN 14 AND 99
      THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS troponin_category
  FROM TroponinInfo AS ti
)
SELECT
  COUNT(tc.subject_id) AS total_count,
  tc.troponin_category
FROM TroponinCategory AS tc
JOIN AdmissionInfo AS ai
  ON tc.subject_id = ai.subject_id AND tc.hadm_id = ai.hadm_id
JOIN DiagnosisInfo AS di
  ON tc.subject_id = di.subject_id AND tc.hadm_id = di.hadm_id
WHERE
  ai.admittime BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY
  tc.troponin_category;