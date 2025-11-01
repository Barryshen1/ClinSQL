WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 45
),
AdmissionsInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%acute myocardial infarction%'
    AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one
),
LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    l.valueuom AS troponin_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL' -- Assuming standard unit for Troponin T
),
InitialLabs AS (
  SELECT
    ai.subject_id,
    ai.hadm_id,
    li.charttime,
    li.troponin_value,
    li.troponin_uom
  FROM AdmissionsInfo AS ai
  JOIN LabInfo AS li
    ON ai.subject_id = li.subject_id AND ai.hadm_id = li.hadm_id
  WHERE
    li.charttime < ai.admittime + INTERVAL '1' HOUR -- Define initial lab as within 1 hour of admission
)
SELECT
  CASE
    WHEN il.troponin_value < 0.01 THEN 'Normal'
    WHEN il.troponin_value >= 0.01 AND il.troponin_value < 0.1 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_category,
  COUNT(*) AS count
FROM InitialLabs AS il
GROUP BY
  troponin_category
ORDER BY
  troponin_category;