WITH ACS_Patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND d.icd_code LIKE '410%' -- ACS ICD-10 codes start with 410
    AND p.anchor_age = 57
),
Troponin_Measurements AS (
  SELECT
    le.subject_id,
    le.valuenum AS troponin_value,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    li.label LIKE '%Troponin%'
    AND le.subject_id IN (
      SELECT
        subject_id
      FROM ACS_Patients
    )
)
SELECT
  MIN(troponin_value) AS min_troponin
FROM Troponin_Measurements;