WITH PatientACS AS (
  -- Identify patients admitted with ACS
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%Acute Myocardial Infarction%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
FirstTroponin AS (
  -- Find the first Troponin I measurement for each patient admission
  SELECT
    le.subject_id,
    le.hadm_id,
    MIN(le.charttime) AS first_charttime,
    le.valuenum AS troponin_value,
    le.valueuom AS troponin_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    li.label = 'Troponin I'
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.subject_id,
    le.hadm_id
),
FilteredPatients AS (
  -- Filter patients based on age, gender, ACS diagnosis, and initial Troponin I value
  SELECT
    pa.subject_id,
    pa.hadm_id
  FROM PatientACS AS pa
  JOIN FirstTroponin AS ft
    ON pa.subject_id = ft.subject_id AND pa.hadm_id = ft.hadm_id
  WHERE
    ft.troponin_value > 0.04
    AND ft.troponin_uom = 'ng/mL'
)
-- Calculate counts and statistics
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(troponin_value) AS mean_troponin,
  STDDEV(troponin_value) AS sd_troponin,
  MIN(troponin_value) AS min_troponin,
  MAX(troponin_value) AS max_troponin
FROM FilteredPatients AS fp
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON fp.subject_id = le.subject_id AND fp.hadm_id = le.hadm_id
WHERE
  le.itemid IN (
    SELECT
      itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
      label = 'Troponin I'
  )
  AND le.valuenum IS NOT NULL
  AND le.valueuom = 'ng/mL'
  AND le.charttime = (
    SELECT;