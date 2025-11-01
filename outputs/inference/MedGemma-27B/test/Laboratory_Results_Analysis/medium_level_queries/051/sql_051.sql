WITH ACS_Patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type = 'EMERGENCY'
),
ACS_Diagnosis AS (
  SELECT DISTINCT
    acs.subject_id,
    acs.hadm_id
  FROM ACS_Patients AS acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON acs.subject_id = d.subject_id AND acs.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('410', '411', '413', '414', '427', '428') -- ACS ICD-10 codes
),
First_TnT AS (
  SELECT
    acs.subject_id,
    acs.hadm_id,
    le.value AS tnt_value,
    le.valueuom AS tnt_unit,
    le.charttime AS tnt_charttime
  FROM ACS_Diagnosis AS acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON acs.subject_id = le.subject_id AND acs.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE
    li.label = 'TnT'
    AND le.charttime >= acs.admittime -- Ensure TnT is measured after admission
    AND le.charttime < (
      SELECT
        MIN(a.dischtime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.subject_id = acs.subject_id AND a.hadm_id = acs.hadm_id
    )
    AND le.charttime < (
      SELECT
        MIN(a.deathtime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.subject_id = acs.subject_id AND a.hadm_id = acs.hadm_id
    )
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY acs.subject_id, acs.hadm_id ORDER BY le.charttime ASC) = 1
),
TnT_Categorized AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN tnt_value < 0.01 THEN 'Normal'
      WHEN tnt_value < 0.1 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS tnt_category
  FROM First_TnT
  WHERE
    tnt_value IS NOT NULL
    AND tnt_unit = 'ng/mL'
)
SELECT
  tnt_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  (COUNT(DISTINCT subject_id) * 100.0 / COUNT(DISTINCT subject_id)) AS percentage,
  AVG(a.los) AS mean_los
FROM TnT_Categorized AS tnt
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON tnt.hadm_id = a.hadm_id
GROUP BY
  tnt_category
ORDER BY
  tnt_category;