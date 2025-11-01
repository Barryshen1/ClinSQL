WITH admissions_acs AS (
  -- Identify ACS admissions for 77-87 year old females and classify as primary/secondary
  SELECT
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.deathtime) AS endtime,
    CASE
      WHEN MAX(CASE WHEN d.icd_code LIKE 'I2%' AND d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS acs_type,
    DATE_DIFF(DATE(COALESCE(a.dischtime, a.deathtime)), DATE(a.admittime), DAY) + 1 AS length_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.hadm_id = a.hadm_id
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'F'
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.deathtime
  HAVING
    MAX(CASE WHEN d.icd_code LIKE 'I2%' AND d.seq_num = 1 THEN 1 ELSE 0 END) = 1
     OR MAX(CASE WHEN d.icd_code LIKE 'I2%' THEN 1 ELSE 0 END) = 1
),
admissions_bucket AS (
  -- Bucket stays into 1-4 vs 5-8 days
  SELECT
    hadm_id,
    admittime,
    endtime,
    acs_type,
    length_days,
    CASE
      WHEN length_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN length_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS length_group
  FROM admissions_acs
  WHERE acs_type IS NOT NULL
),
imaging_counts AS (
  -- Imaging (radiology/CT) counts per admission within stay window
  SELECT
    ab.hadm_id,
    SUM(
      CASE
        WHEN ce.charttime IS NOT NULL
             AND ce.charttime >= ab.admittime
             AND ce.charttime <= ab.endtime
             AND (di.category LIKE '%Radiology%' OR LOWER(di.label) LIKE '%x-ray%' OR LOWER(di.label) LIKE '%ct%')
        THEN 1
        ELSE 0
      END
    ) AS imaging_count
  FROM admissions_bucket AS ab
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = ab.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  GROUP BY ab.hadm_id
)
SELECT
  ab.acs_type,
  ab.length_group,
  -- Use COALESCE to treat missing imaging as 0
  AVG(COALESCE(ic.imaging_count, 0)) AS mean_count,
  MIN(COALESCE(ic.imaging_count, 0)) AS min_count,
  MAX(COALESCE(ic.imaging_count, 0)) AS max_count
FROM admissions_bucket AS ab
LEFT JOIN imaging_counts AS ic
  ON ic.hadm_id = ab.hadm_id
GROUP BY ab.acs_type, ab.length_group
ORDER BY ab.acs_type, ab.length_group;