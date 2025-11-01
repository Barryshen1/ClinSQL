WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.deathtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND ic.los > 0 -- Ensure ICU stay is valid
), DiagnosisCohort AS (
  SELECT
    pc.subject_id,
    pc.stay_id,
    pc.intime,
    pc.outtime,
    pc.los,
    pc.deathtime,
    di.icd_code
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON pc.subject_id = di.subject_id
    AND pc.stay_id = di.stay_id -- Link diagnoses to ICU stay
  WHERE
    di.icd_code LIKE 'J18%' -- Pneumonia ICD-10 codes
), InstabilityScore AS (
  SELECT
    dc.subject_id,
    dc.stay_id,
    dc.intime,
    dc.outtime,
    dc.los,
    dc.deathtime,
    ce.charttime,
    ce.valuenum AS instability_score
  FROM DiagnosisCohort AS dc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON dc.subject_id = ce.subject_id
    AND dc.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220184 -- Instability Score itemid
    AND ce.charttime BETWEEN dc.intime AND TIMESTAMP_ADD(dc.intime, INTERVAL 24 HOUR)
), ScoreDistribution AS (
  SELECT
    subject_id,
    stay_id,
    instability_score,
    PERCENT_RANK() OVER (PARTITION BY stay_id ORDER BY instability_score) AS score_percentile
  FROM InstabilityScore
), DecileCalculation AS (
  SELECT
    subject_id,
    stay_id,
    instability_score,
    score_percentile,
    CASE
      WHEN score_percentile <= 0.1 THEN 1
      ELSE 0
    END AS is_most_unstable_decile
  FROM ScoreDistribution
), MostUnstableDecile AS (
  SELECT
    dc.subject_id,
    dc.stay_id,
    dc.intime,
    dc.outtime,
    dc.los,
    dc.deathtime,
    dc.instability_score,
    dc.score_percentile,
    dc.is_most_unstable_decile
  FROM DiagnosisCohort AS dc
  JOIN DecileCalculation AS dcalc
    ON dc.subject_id = dcalc.subject_id
    AND dc.stay_id = dcalc.stay_id
  WHERE
    dcalc.is_most_unstable_decile = 1
)
SELECT
  -- Calculate the percentile for the specific score of 60
  (
    SELECT
      score_percentile
    FROM ScoreDistribution
    WHERE
      instability_score = 60
  ) AS percentile_for_score_60,
  -- Calculate average ICU LOS and mortality for the most unstable decile
  AVG(los) AS avg_icu_los_most_unstable_decile,
  AVG(CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality_most_unstable_decile
FROM MostUnstableDecile;