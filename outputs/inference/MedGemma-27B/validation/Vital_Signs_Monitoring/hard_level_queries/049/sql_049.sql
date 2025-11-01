WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88
), SepsisDiagnosis AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id
  FROM PatientInfo AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('A41.9', 'A41.4', 'A41.5', 'A41.2', 'A41.1', 'A41.3', 'A41.0', 'A41.8', 'A41.7', 'A41.6', 'R65.21', 'R65.20', 'R65.29', 'R57.2', 'R57.1', 'R57.0', 'R57.8', 'R57.9', 'R57.81', 'R57.82', 'R57.83', 'R57.84', 'R57.85', 'R57.86', 'R57.87', 'R57.88', 'R57.89', 'R57.891', 'R57.892', 'R57.893', 'R57.894', 'R57.895', 'R57.896', 'R57.897', 'R57.898', 'R57.899', 'R57.899')
), ICUStays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  INNER JOIN SepsisDiagnosis AS sd
    ON s.subject_id = sd.subject_id AND s.hadm_id = sd.hadm_id
), InstabilityScore AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.charttime,
    ic.valuenum AS instability_score
  FROM ICUStays AS ic
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.subject_id = ce.subject_id AND ic.hadm_id = ce.hadm_id AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220180 -- Instability Score
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
), ScorePercentile AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    PERCENT_RANK() OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY instability_score) AS percentile_rank
  FROM InstabilityScore
)
SELECT
  AVG(CASE WHEN percentile_rank >= 0.75 THEN instability_score ELSE NULL END) AS avg_instability_score_q4,
  AVG(CASE WHEN percentile_rank >= 0.75 THEN los ELSE NULL END) AS avg_icu_los_q4,
  AVG(CASE WHEN percentile_rank >= 0.75 THEN hospital_expire_flag ELSE NULL END) AS hospital_mortality_q4
FROM ScorePercentile;