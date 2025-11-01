WITH DKA_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = '250.00' -- DKA code
    AND a.gender = 'F'
    AND a.anchor_age = 58
), Glucose_Measurements AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.charttime,
    g.valuenum AS glucose_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS g
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS l
    ON g.itemid = l.itemid
  WHERE
    l.label = 'Glucose'
    AND g.valueuom = 'mg/dL'
    AND g.subject_id IN (
      SELECT
        subject_id
      FROM DKA_Admissions
    )
    AND g.hadm_id IN (
      SELECT
        hadm_id
      FROM DKA_Admissions
    )
), Peak_Glucose AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(glucose_value) AS peak_glucose
  FROM Glucose_Measurements
  GROUP BY
    subject_id,
    hadm_id
)
SELECT
  AVG(peak_glucose) AS median_peak_glucose
FROM Peak_Glucose;