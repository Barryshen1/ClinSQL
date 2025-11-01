WITH first_gcs AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS gcs_total,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    icu.subject_id = ce.subject_id 
    AND icu.stay_id = ce.stay_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age >= 77
    AND pat.anchor_age <= 87
    AND ce.itemid = 220742
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
)
SELECT 
  AVG(gcs_total) AS avg_first_gcs_total
FROM 
  first_gcs
WHERE rn = 1;