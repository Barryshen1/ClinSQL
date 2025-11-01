WITH ich_cohort AS (
  -- Identify admissions with ICH
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE a.dischtime IS NOT NULL
    AND (
       LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%' OR
       LOWER(dd.long_title) LIKE '%intracranial hemorrhage%' OR
       di.icd_code LIKE 'I61%' OR
       di.icd_code LIKE '431%' OR
       di.icd_code LIKE '432%'
    )
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag,
         p.anchor_age, p.gender
  FROM ich_cohort ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ic.subject_id = a.subject_id AND ic.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 73 AND 83
    AND LOWER(p.gender) IN ('m','male')
    AND a.dischtime IS NOT NULL
),
labs_abnormal AS (
  SELECT c.subject_id, c.hadm_id, l.itemid,
         MAX(CASE 
               WHEN l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower THEN 1
               WHEN l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper THEN 1
               ELSE 0
             END) AS abnormal
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, l.itemid
),
instability AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT CASE WHEN la.abnormal = 1 THEN la.itemid END) AS instability_count
  FROM cohort c
  LEFT JOIN labs_abnormal la
    ON la.subject_id = c.subject_id AND la.hadm_id = c.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
admission_metrics AS (
  SELECT c.subject_id, c.hadm_id,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND)/3600.0 AS los_hrs,
         COALESCE(i.instability_count, 0) AS instability_count,
         CASE WHEN c.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM cohort c
  LEFT JOIN instability i
    ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),
quartile_rank AS (
  SELECT subject_id, hadm_id, los_hrs, instability_count, mortality,
         NTILE(4) OVER (ORDER BY instability_count) AS quartile
  FROM admission_metrics
)
, quartile_summary AS (
  SELECT quartile, COUNT(*) AS count_in_quartile,
         AVG(los_hrs) AS mean_los_hrs,
         AVG(mortality) AS mortality_rate
  FROM (
    SELECT q.quartile, am.los_hrs, am.mortality
    FROM quartile_rank q
    JOIN admission_metrics am
      ON am.subject_id = q.subject_id AND am.hadm_id = q.hadm_id
  ) t
  GROUP BY quartile
)
, all_inpatients AS (
  SELECT 0 AS quartile, COUNT(*) AS count_in_quartile,
         AVG(los_hrs) AS mean_los_hrs,
         AVG(mortality) AS mortality_rate
  FROM admission_metrics
)
SELECT *
FROM (
  SELECT * FROM quartile_summary
  UNION ALL
  SELECT * FROM all_inpatients
)
ORDER BY quartile;