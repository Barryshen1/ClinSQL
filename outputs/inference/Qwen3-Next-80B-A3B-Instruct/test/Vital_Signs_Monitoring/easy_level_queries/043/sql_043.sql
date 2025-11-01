WITH first_gcs AS (
  SELECT 
    i.stay_id,
    c.valuenum AS gcs_total,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(d.label) LIKE '%gcs%total%'
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 3 AND 15  -- clinically plausible range
)
SELECT 
  AVG(gcs_total) AS average_first_gcs_total
FROM 
  first_gcs
WHERE 
  rn = 1;