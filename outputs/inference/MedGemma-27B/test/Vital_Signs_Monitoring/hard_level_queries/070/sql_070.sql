WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%hyperosmolar hyperglycemic state%'
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN DiagnosisInfo AS di
    ON i.subject_id = di.subject_id AND i.hadm_id = di.hadm_id
), VitalSigns AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum AS value,
    c.valueuom AS unit
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE
    di.label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
    AND c.stay_id IN (
      SELECT
        stay_id
      FROM ICUStayInfo
    )
), HourlyVitals AS (
  SELECT
    subject_id,
    stay_id,
    DATE_TRUNC(charttime, HOUR) AS hour_start,
    AVG(CASE WHEN di.label = 'Heart Rate' THEN c.value END) AS avg_hr,
    AVG(CASE WHEN di.label = 'Mean Arterial Pressure' THEN c.value END) AS avg_map,
    AVG(CASE WHEN di.label = 'Respiratory Rate' THEN c.value END) AS avg_rr
  FROM VitalSigns AS c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON c.itemid = di.itemid
  GROUP BY
    subject_id,
    stay_id,
    hour_start
), CV_Sum AS (
  SELECT
    subject_id,
    stay_id,
    hour_start,
    (avg_hr + avg_map + avg_rr) AS cv_sum
  FROM HourlyVitals
), TopQuartile AS (
  SELECT
    subject_id,
    stay_id,
    hour_start,
    cv_sum,
    PERCENT_RANK() OVER (PARTITION BY subject_id, stay_id ORDER BY cv_sum DESC) AS cv_rank
  FROM CV_Sum
  WHERE
    cv_sum IS NOT NULL
), InstabilityScore AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.los,
    i.hospital_expire_flag,
    COUNT(DISTINCT CASE WHEN c.itemid IN (SELECT itemid FROM d_items WHERE label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')) THEN c.itemid END) AS abnormal_vital_count,
    -- Calculate stay instability score (example: sum of deviations from;