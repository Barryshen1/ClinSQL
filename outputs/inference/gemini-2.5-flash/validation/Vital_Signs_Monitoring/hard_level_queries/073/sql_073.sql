WITH
  ich_cohort AS (
    -- Select female patients aged 47-57 with Intracranial Hemorrhage and an ICU stay
    SELECT DISTINCT
      p.subject_id,
      a.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.outtime,
      icu.los,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 47 AND 57
      AND (
        di.icd_code LIKE 'I60%' -- Intracranial hemorrhage
        OR di.icd_code LIKE 'I61%' -- Intracerebral hemorrhage
        OR di.icd_code LIKE 'I62%' -- Other nontraumatic intracranial hemorrhage
      )
  ),
  vital_sign_scores AS (
    -- Calculate vital sign instability score for each ICU stay within the first 72 hours
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.los,
      ic.hospital_expire_flag,
      SUM(
        CASE
          WHEN ce.itemid IN (220045)
          THEN -- Heart Rate
            CASE
              WHEN ce.valuenum < 40
              OR ce.valuenum > 120 THEN 3
              WHEN (
                ce.valuenum >= 40
                AND ce.valuenum <= 50
              )
              OR (
                ce.valuenum >= 100
                AND ce.valuenum <= 120
              ) THEN 1
              ELSE 0
            END
          WHEN ce.itemid IN (220210)
          THEN -- Respiratory Rate
            CASE
              WHEN ce.valuenum < 8
              OR ce.valuenum > 25 THEN 3
              WHEN (
                ce.valuenum >= 8
                AND ce.valuenum <= 10
              )
              OR (
                ce.valuenum >= 20
                AND ce.valuenum <= 25
              ) THEN 1
              ELSE 0
            END
          WHEN ce.itemid IN (220050, 220179)
          THEN -- Systolic Blood Pressure
            CASE
              WHEN ce.valuenum < 90
              OR ce.valuenum > 200 THEN 3
              WHEN (
                ce.valuenum >= 90
                AND ce.valuenum <= 100
              )
              OR (
                ce.valuenum >= 180
                AND ce.valuenum <= 200
              ) THEN 1
              ELSE 0
            END
          WHEN ce.itemid IN (223761)
          THEN -- Temperature Fahrenheit
            CASE
              WHEN ce.valuenum < 96
              OR ce.valuenum > 102.2 THEN 3
              WHEN (
                ce.valuenum >= 96
                AND ce.valuenum <= 96.9
              )
              OR (
                ce.valuenum >= 100.4
                AND ce.valuenum <= 102.2
              ) THEN 1
              ELSE 0
            END
          WHEN ce.itemid IN (220277)
          THEN -- SpO2
            CASE
              WHEN ce.valuenum < 85 THEN 3
              WHEN (
                ce.valuenum >= 85
                AND ce.valuenum <= 90
              ) THEN 1
              ELSE 0
            END
          ELSE
            0
        END
      ) AS instability_score
    FROM
      ich_cohort ic
      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ic.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN ic.intime AND DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0
    GROUP BY
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.los,
      ic.hospital_expire_flag
  ),
  ranked_scores AS (
    -- Rank instability scores and assign deciles
    SELECT
      *,
      PERCENT_RANK() OVER (
        ORDER BY
          instability_score
      ) AS percentile_rank,
      NTILE(10) OVER (
        ORDER BY
          instability_score DESC
      ) AS decile
    FROM
      vital_sign_scores
  )
SELECT
  -- Get the percentile for a vital-sign instability score of 75
  (SELECT
      AVG(percentile_rank) * 100
    FROM
      ranked_scores
    WHERE
      instability_score = 75
  ) AS percentile_for_score_75,
  -- Get average ICU length of stay for the top decile (highest instability scores)
  (SELECT
      AVG(los)
    FROM
      ranked_scores
    WHERE
      decile = 1
  ) AS avg_icu_los_top_decile,
  -- Get mortality rate for the top decile
  (SELECT
      AVG(hospital_expire_flag) * 100
    FROM
      ranked_scores
    WHERE
      decile = 1
  ) AS mortality_rate_top_decile;