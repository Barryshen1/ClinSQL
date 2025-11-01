WITH PatientAgeGender AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age BETWEEN 41 AND 51
    AND p.gender = 'F'
),
ICUStays AS (
  SELECT
    s.subject_id,
    s.hadm_id, -- Added hadm_id to ICUStays
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        p.subject_id
      FROM
        PatientAgeGender AS p
    )
),
MAPMeasurements AS (
  SELECT
    i.subject_id,
    i.hadm_id, -- Added hadm_id to MAPMeasurements
    i.stay_id,
    i.charttime,
    i.valuenum AS map_value,
    i.valueuom AS map_uom
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS i
  WHERE
    i.itemid = 455
    AND i.stay_id IN (
      SELECT
        s.stay_id
      FROM
        ICUStays AS s
    )
),
MAPCategories AS (
  SELECT
    subject_id,
    stay_id,
    hadm_id, -- Added hadm_id to MAPCategories
    charttime,
    map_value,
    map_uom,
    CASE
      WHEN map_value < 65 THEN '<65'
      WHEN map_value BETWEEN 65 AND 74 THEN '65–74'
      WHEN map_value BETWEEN 75 AND 84 THEN '75–84'
      WHEN map_value >= 85 THEN '≥85'
      ELSE NULL
    END AS map_category
  FROM
    MAPMeasurements
  WHERE
    map_uom = 'mmHg'
),
StrokeDiagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE 'I6%'
    AND d.icd_version = 9
),
StrokePatients AS (
  SELECT DISTINCT
    s.subject_id,
    s.hadm_id, -- Added hadm_id to StrokePatients
    s.stay_id
  FROM
    ICUStays AS s
  JOIN
    StrokeDiagnosis AS sd
    ON s.subject_id = sd.subject_id
    AND s.hadm_id = sd.hadm_id
)
SELECT
  mc.map_category,
  COUNT(DISTINCT mc.subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN sp.subject_id IS NOT NULL THEN mc.subject_id ELSE NULL END) AS stroke_count
FROM
  MAPCategories AS mc
LEFT JOIN
  StrokePatients AS sp
  ON mc.subject_id = sp.subject_id
  AND mc.hadm_id = sp.hadm_id -- Added hadm_id to the join condition
  AND mc.stay_id = sp.stay_id
GROUP BY
  mc.map_category
ORDER BY
  mc.map_category;