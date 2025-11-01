SELECT STDDEV(max_resp_rate) AS sd_max_resp_rate
FROM (
  SELECT 
    ce.subject_id,
    MAX(ce.valuenum) AS max_resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND ce.itemid IN (220210, 224422)  -- Respiratory Rate itemids
    AND ce.valuenum IS NOT NULL        -- Ensure numeric values
  GROUP BY ce.subject_id
) AS patient_max_resp;