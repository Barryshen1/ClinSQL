WITH cohort_f AS (
  -- Identify female inpatients aged 53-63 with a cardiac arrest diagnosis during admission
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND di.icd_code LIKE 'I46%'
),

lab_changes AS (
  -- Lab measurements within 48h of admission with previous value per item
  SELECT c.subject_id, c.hadm_id, l.charttime, l.valuenum, l.itemid,
         LAG(l.valuenum) OVER (PARTITION BY l.subject_id, l.hadm_id, l.itemid ORDER BY l.charttime) AS prev_val
  FROM cohort_f AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
),

instability AS (
  -- 48-hour lab instability score per admission
  SELECT subject_id, hadm_id,
         SUM(CASE
               WHEN prev_val IS NULL THEN 0
               WHEN valuenum IS NULL THEN 0
               ELSE CASE
                      WHEN ABS(valuenum - prev_val) > GREATEST(0.2 * ABS(prev_val), 0.01)
                        THEN 1
                      ELSE 0
                    END
             END) AS lab_instability_score
  FROM lab_changes
  GROUP BY subject_id, hadm_id
),

p90 AS (
  -- compute 90th percentile of lab_instability_score across all rows in instability
  SELECT quant AS p90
  FROM (
    SELECT APPROX_QUANTILES(lab_instability_score, 100) AS q
    FROM instability
  ) AS t
  CROSS JOIN UNNEST(t.q) AS quant WITH OFFSET AS pos
  WHERE pos = 90
  LIMIT 1
),

high_group AS (
  SELECT i.subject_id, i.hadm_id
  FROM instability AS i CROSS JOIN p90
  WHERE i.lab_instability_score >= p90.p90
),

high_details AS (
  SELECT hg.hadm_id, hg.subject_id,
         a.admittime, a.dischtime, a.hospital_expire_flag,
         i.lab_instability_score
  FROM high_group AS hg
  JOIN cohort_f AS a
    ON hg.hadm_id = a.hadm_id AND hg.subject_id = a.subject_id
  LEFT JOIN instability AS i
    ON hg.hadm_id = i.hadm_id AND hg.subject_id = i.subject_id
),

crit_high AS (
  SELECT hd.hadm_id, hd.subject_id, COUNT(*) AS crit_count
  FROM high_details AS hd
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = hd.hadm_id AND le.subject_id = hd.subject_id
   AND le.charttime BETWEEN hd.admittime AND TIMESTAMP_ADD(hd.admittime, INTERVAL 48 HOUR)
   AND (le.flag = 'Critical' OR LOWER(le.flag) LIKE '%critical%')
  GROUP BY hd.hadm_id, hd.subject_id
),

crit_all AS (
  SELECT c.hadm_id, c.subject_id, COUNT(*) AS crit_count
  FROM cohort_f AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = c.hadm_id AND le.subject_id = c.subject_id
   AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
   AND (le.flag = 'Critical' OR LOWER(le.flag) LIKE '%critical%')
  GROUP BY c.hadm_id, c.subject_id
),

final AS (
  SELECT hd.hadm_id, hd.subject_id,
         hd.admittime, hd.dischtime, hd.hospital_expire_flag,
         hd.lab_instability_score,
         c_high.crit_count AS crit_high_group,
         c_all.crit_count AS crit_all_group
  FROM high_details AS hd
  LEFT JOIN crit_high AS c_high
    ON hd.hadm_id = c_high.hadm_id AND hd.subject_id = c_high.subject_id
  LEFT JOIN crit_all AS c_all
    ON hd.hadm_id = c_all.hadm_id AND hd.subject_id = c_all.subject_id
)

SELECT
  p90.p90 AS p90_value,
  COUNT(*) AS high_group_count,
  SUM(hospital_expire_flag) AS high_group_deaths,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(COALESCE(crit_high_group, 0)) AS mean_crit_high_group,
  AVG(COALESCE(crit_all_group, 0)) AS mean_crit_all_group,
  SAFE_DIVIDE( AVG(COALESCE(crit_high_group, 0)),
               NULLIF( AVG(COALESCE(crit_all_group, 0)), 0) ) AS crit_ratio
FROM final
CROSS JOIN p90;