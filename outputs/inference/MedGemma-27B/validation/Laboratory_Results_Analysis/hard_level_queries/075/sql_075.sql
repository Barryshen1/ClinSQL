WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code = '4531' -- DVT code
), LabInfo AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE
        category = 'Laboratory'
        AND label IN ('Creatinine', 'BUN', 'Potassium', 'Sodium', 'Glucose', 'Bicarbonate', 'Calcium', 'Magnesium', 'Phosphate', 'Hemoglobin', 'Platelet Count', 'White Blood Cell Count')
    )
), LabInstabilityScore AS (
  SELECT
    l1.subject_id,
    l1.hadm_id,
    l1.charttime,
    (
      CASE
        WHEN l1.itemid = 1501 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1502 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1503 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1504 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1505 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1506 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1507 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_id, l1.itemid ORDER BY l1.charttime))
        WHEN l1.itemid = 1508 THEN ABS(l1.valuenum - lag(l1.valuenum, 1, l1.valuenum) OVER (PARTITION BY l1.subject_id, l1.hadm_;