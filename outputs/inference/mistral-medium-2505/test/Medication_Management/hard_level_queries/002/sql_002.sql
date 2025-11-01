WITH
-- Identify male patients aged 67-77 with AMI
ami_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code LIKE 'I21.%'  -- AMI ICD-10 codes
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Calculate medication complexity score for first 24 hours
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    -- Count distinct medications
    COUNT(DISTINCT
      CASE
        WHEN medication IS NOT NULL THEN medication
        ELSE NULL
      END
    ) AS distinct_med_count,
    -- Count different routes
    COUNT(DISTINCT
      CASE
        WHEN route IS NOT NULL THEN route
        ELSE NULL
      END
    ) AS distinct_route_count,
    -- Count different frequencies
    COUNT(DISTINCT
      CASE
        WHEN frequency IS NOT NULL THEN frequency
        ELSE NULL
      END
    ) AS distinct_frequency_count
  FROM (
    -- Combine all medication sources
    SELECT
      p.subject_id,
      p.hadm_id,
      p.medication,
      p.route,
      p.frequency
    FROM
      `physionet-data.mimiciv_3_1_hosp.pharmacy` p
    JOIN
      ami_patients a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
    WHERE
      p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)

    UNION ALL

    SELECT
      e.subject_id,
      e.hadm_id,
      e.medication,
      NULL AS route,
      NULL AS frequency
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` e
    JOIN
      ami_patients a ON e.subject_id = a.subject_id AND e.hadm_id = a.hadm_id
    WHERE
      e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)

    UNION ALL

    SELECT
      i.subject_id,
      i.hadm_id,
      d.label AS medication,
      NULL AS route,
      NULL AS frequency
    FROM
      `physionet-data.mimiciv_3_1_icu.inputevents` i
    JOIN
      `physionet-data.mimiciv_3_1_icu.d_items` d ON i.itemid = d.itemid
    JOIN
      ami_patients a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    WHERE
      i.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
      AND d.category = 'Medication'
  )
  GROUP BY
    subject_id, hadm_id
),

-- Calculate complexity score (simple version: sum of distinct counts)
complexity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    (distinct_med_count + distinct_route_count + distinct_frequency_count) AS complexity_score
  FROM
    med_complexity
),

-- Assign tertiles based on complexity score
tertiles AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.complexity_score,
    NTILE(3) OVER (ORDER BY c.complexity_score) AS tertile
  FROM
    complexity_scores c
),

-- Calculate 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id AND a1.hadm_id != a2.hadm_id
  WHERE
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) BETWEEN 1 AND 30
    AND a1.hadm_id IN (SELECT hadm_id FROM tertiles)
)

-- Final aggregation by tertile
SELECT
  t.tertile,
  COUNT(DISTINCT t.hadm_id) AS admission_count,
  MIN(t.complexity_score) AS min_score,
  MAX(t.complexity_score) AS max_score,
  ROUND(AVG(t.complexity_score), 2) AS mean_score,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)), 2) AS mean_los_days,
  ROUND(100 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT t.hadm_id), 2) AS in_hospital_mortality_pct,
  ROUND(100 * COUNT(DISTINCT r.original_hadm_id) / COUNT(DISTINCT t.hadm_id), 2) AS thirty_day_readmission_pct
FROM
  tertiles t
JOIN
  ami_patients a ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
LEFT JOIN
  readmissions r ON t.hadm_id = r.original_hadm_id
GROUP BY
  t.tertile
ORDER BY
  t.tertile;