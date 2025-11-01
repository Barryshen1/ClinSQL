SELECT 
    a1.hadm_id AS initial_hadm_id,
    COUNT(DISTINCT a2.hadm_id) AS readmissions
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON a1.subject_id = a2.subject_id
  WHERE 
    a2.admittime BETWEEN TIMESTAMP_ADD(a1.dischtime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
    AND a1.dischtime IS NOT NULL
  GROUP BY 
    a1.hadm_id
)

-- Incorporate 30-day readmission into outcomes
final_outcomes AS (
  SELECT 
    o.quartile,
    o.admissions,
    o.score_range,
    o.los,
    o.mortality,
    COALESCE(r.readmissions / o.admissions * 100, 0) AS thirty_day_readmission
  FROM 
    outcomes o
  LEFT JOIN 
    readmissions r
      ON o.hadm_id = r.initial_hadm_id
)

SELECT 
  quartile,
  admissions,
  score_range,
  los,
  mortality,
  thirty_day_readmission
FROM 
  final_outcomes
ORDER BY 
  quartile;