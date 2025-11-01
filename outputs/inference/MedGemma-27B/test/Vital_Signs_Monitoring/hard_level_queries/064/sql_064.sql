WITH PatientCohort AS (
  -- Select subject_ids of male patients aged 45-55 admitted to the ICU
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),
ARFPatients AS (
  -- Select subject_ids of patients with ARF diagnosis
  SELECT DISTINCT
    d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%Acute Renal Failure%'
    OR di.long_title LIKE '%Acute Kidney Failure%'
),
InstabilityScore AS (
  -- Calculate the composite instability score for each patient
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    -- Calculate the score based on MAP, HR, RR, and SpO2
    (
      CASE
        WHEN ce_map.valuenum < 65 THEN 1
        ELSE 0
      END + CASE
        WHEN ce_hr.valuenum > 100 THEN 1
        ELSE 0
      END + CASE
        WHEN ce_rr.valuenum > 25 THEN 1
        ELSE 0
      END + CASE
        WHEN ce_spo2.valuenum < 90 THEN 1
        ELSE 0
      END
    ) AS composite_instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_map
    ON icu.stay_id = ce_map.stay_id AND ce_map.itemid = 455 -- MAP
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_hr
    ON icu.stay_id = ce_hr.stay_id AND ce_hr.itemid = 220187 -- HR
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_rr
    ON icu.stay_id = ce_rr.stay_id AND ce_rr.itemid = 220210 -- RR
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_spo2
    ON icu.stay_id = ce_spo2.stay_id AND ce_spo2.itemid = 220267 -- SpO2
  WHERE
    icu.intime BETWEEN TIMESTAMP_SUB(icu.intime, INTERVAL 48 HOUR) AND icu;