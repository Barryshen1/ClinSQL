WITH qualifying_stays AS (
  SELECT 
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    AVG(ce.valuenum) AS avg_sbp_first_24h
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 1 DAY)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND di.label LIKE '%SBP%' OR di.label LIKE '%systolic%'
    AND icu.los > 0
  GROUP BY 
    icu.stay_id, pat.gender, pat.anchor_age
  HAVING 
    avg_sbp_first_24h IS NOT NULL
),
percentile_calc AS (
  SELECT 
    stay_id,
    avg_sbp_first_24h,
    PERCENT_RANK() OVER (ORDER BY avg_sbp_first_24h) AS percentile_rank
  FROM 
    qualifying_stays
)
SELECT 
  100 * FIRST_VALUE(percentile_rank) OVER (
    ORDER BY 
      CASE WHEN avg_sbp_first_24h <= 150 THEN 0 ELSE 1 END,
      avg_sbp_first_24h
  ) AS percentile_for_150
FROM 
  percentile_calc
LIMIT 1;