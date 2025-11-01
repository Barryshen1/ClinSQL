WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
), ICUStays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
), SystolicBloodPressure AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS systolic_bp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.itemid = 455 -- Systolic blood pressure
), PatientICUStayInfo AS (
  SELECT
    ps.subject_id,
    ps.gender,
    ps.anchor_age,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    PatientDemographics AS ps
    JOIN ICUStays AS ic ON ps.subject_id = ic.subject_id
  WHERE
    ps.gender = 'M' AND ps.anchor_age BETWEEN 40 AND 50
), First48hSBP AS (
  SELECT
    psic.subject_id,
    psic.hadm_id,
    psic.stay_id,
    psic.intime,
    sbp.charttime,
    sbp.systolic_bp
  FROM
    PatientICUStayInfo AS psic
    JOIN SystolicBloodPressure AS sbp ON psic.subject_id = sbp.subject_id AND psic.hadm_id = sbp.hadm_id AND psic.stay_id = sbp.stay_id
  WHERE
    sbp.charttime BETWEEN psic.intime AND TIMESTAMP_ADD(psic.intime, INTERVAL 48 HOUR)
), SBPStats AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(systolic_bp) AS mean_sbp
  FROM
    First48hSBP
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
), SBPCategories AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140–159'
      ELSE '≥160'
    END AS sbp_category
  FROM
    SBPStats
), SBPCategoryCounts AS (
  SELECT
    sbp_category,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    SBPCategories
  GROUP BY
    sbp_category
), SBPCategoryPercentages AS (
  SELECT
    sbp_category,
    patient_count,
    (patient_count / SUM(patient_count) OVER ()) * 100 AS percentage
  FROM
    SBPCategoryCounts
), MI_Diagnoses AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  WHERE
    di.icd_code LIKE 'I21%' -- MI codes
), MI_Rates AS (
  SELECT
    sbp.sbp_category,
    COUNT(DISTINCT sbp.subject_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN mi.subject_id IS NOT NULL THEN sbp.subject_id END) AS mi_patients,
    (COUNT(DISTINCT CASE WHEN mi.subject_id IS NOT NULL THEN sbp.subject_id END) / COUNT(DISTINCT sbp.subject_id)) * 100 AS mi_rate
  FROM
    SBPCategories AS sbp
  LEFT JOIN
    MI_Diagnoses AS mi;