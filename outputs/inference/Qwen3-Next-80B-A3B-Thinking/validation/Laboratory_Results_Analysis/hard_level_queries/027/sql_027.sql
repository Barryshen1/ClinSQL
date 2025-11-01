WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      di.long_title LIKE '%gastrointestinal hemorrhage%'
      OR di.long_title LIKE '%hematochezia%'
      OR di.long_title LIKE '%rectal hemorrhage%'
      OR d.icd_code IN ('K92.2', 'K62.5')
    )
),

lab_scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COALESCE(COUNT(l.labevent_id), 0) AS score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.subject_id = l.subject_id 
    AND c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY c.subject_id, c.hadm_id
),

quintiles AS (
  SELECT 
    ls.subject_id,
    ls.hadm_id,
    ls.score,
    NTILE(5) OVER (ORDER BY ls.score) AS quintile
  FROM lab_scores ls
),

overall_avg AS (
  SELECT AVG(score) AS overall_avg_score
  FROM lab_scores
)

SELECT 
  q.quintile,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_los,
  AVG(a.hospital_expire_flag) AS mortality_rate,
  AVG(q.score) AS quintile_avg_score,
  oa.overall_avg_score
FROM quintiles q
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
CROSS JOIN overall_avg oa
GROUP BY q.quintile, oa.overall_avg_score
ORDER BY q.quintile;