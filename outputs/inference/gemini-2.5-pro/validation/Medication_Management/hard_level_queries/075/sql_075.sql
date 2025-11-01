WITH
  -- Step 1: Identify the cohort of male patients aged 58-68
  cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 58 AND 68
      AND a.dischtime IS NOT NULL -- LOS and readmission require a discharge time
  ),
  -- Step 2: Calculate medication complexity score for each admission in the cohort (unique meds in first 72h)
  med_complexity AS (
    SELECT
      c.hadm_id,
      COUNT(DISTINCT emar.medication) AS med_complexity_score
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.emar` AS emar
      ON c.hadm_id = emar.hadm_id
    WHERE
      -- Filter for administrations within the first 72 hours of admission
      emar.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      AND emar.medication IS NOT NULL
    GROUP BY
      c.hadm_id
  ),
  -- Step 3: Calculate 30-day readmission flag for all hospital admissions
  readmission_info AS (
    SELECT
      hadm_id,
      CASE
        WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
        ELSE 0
      END AS readmitted_30_days
    FROM
      (
        SELECT
          hadm_id,
          dischtime,
          LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions`
      )
    WHERE
      next_admittime IS NOT NULL
  ),
  -- Step 4: Combine all patient-level stats and calculate tertiles based on complexity
  patient_stats AS (
    SELECT
      c.hadm_id,
      -- Use COALESCE for patients with no medications in the time window (score=0)
      COALESCE(mc.med_complexity_score, 0) AS med_complexity_score,
      -- Calculate hospital length of stay in days
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      c.hospital_expire_flag,
      COALESCE(ri.readmitted_30_days, 0) AS readmitted_30_days,
      -- Create three groups (tertiles) based on medication complexity score
      NTILE(3) OVER (
        ORDER BY
          COALESCE(mc.med_complexity_score, 0)
      ) AS complexity_tertile
    FROM
      cohort AS c
    LEFT JOIN
      med_complexity AS mc
      ON c.hadm_id = mc.hadm_id
    LEFT JOIN
      readmission_info AS ri
      ON c.hadm_id = ri.hadm_id
  )
-- Step 5: Final aggregation to report metrics for each tertile
SELECT
  complexity_tertile,
  COUNT(hadm_id) AS n,
  MIN(med_complexity_score) AS min_complexity_score,
  MAX(med_complexity_score) AS max_complexity_score,
  ROUND(AVG(med_complexity_score), 2) AS mean_complexity_score,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_pct
FROM
  patient_stats
GROUP BY
  complexity_tertile
ORDER BY
  complexity_tertile;