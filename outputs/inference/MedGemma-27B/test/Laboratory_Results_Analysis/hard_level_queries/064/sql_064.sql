WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'K85' -- ICD-10 code for acute pancreatitis
    AND d.icd_version = 10
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
), PatientICU AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    PatientDiagnosis AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
), LabEvents AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.charttime,
    p.valuenum,
    p.valueuom,
    p.itemid
  FROM
    PatientICU AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON p.subject_id = c.subject_id
    AND p.hadm_id = c.hadm_id
    AND p.stay_id = c.stay_id
  WHERE
    c.itemid IN (50912, 50911, 50910, 50909, 50913, 50914, 50915, 50916, 50917, 50918, 50919, 50920, 50921, 50922, 50923, 50924, 50925, 50926, 50927, 50928, 50929, 50930, 50931, 50932, 50933, 50934, 50935, 50936, 50937, 50938, 50939, 50940, 50941, 50942, 50943, 50944, 50945, 50946, 50947, 50948, 50949, 50950, 50951, 50952, 50953, 50954, 50955, 50;