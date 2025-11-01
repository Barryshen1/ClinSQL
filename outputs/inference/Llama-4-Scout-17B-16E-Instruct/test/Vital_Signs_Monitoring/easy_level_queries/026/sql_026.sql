WITH 
  respiratory_rate_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label = 'Respiratory Rate'
  ),
  
  respiratory_rates AS (
    SELECT 
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.intime,
      cv.charttime,
      cv.valuenum AS respiratory_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` cv 
        ON ic.stay_id = cv.stay_id
    JOIN 
      respiratory_rate_itemid rri 
        ON cv.itemid = rri.itemid
    WHERE 
      cv.valuenum IS NOT NULL 
      AND ic.intime <= cv.charttime 
      AND cv.charttime <= ic.intime + INTERVAL 1 DAY
  ),
  
  patient_info AS (
    SELECT 
      subject_id,
      anchor_age,
      gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE 
      gender = 'M' 
      AND anchor_age BETWEEN 39 AND 49
  )

SELECT 
  pi.anchor_age,
  MIN(rr.respiratory_rate) AS min_respiratory_rate
FROM 
  patient_info pi
JOIN 
  respiratory_rates rr 
    ON pi.subject_id = rr.subject_id
WHERE 
  pi.anchor_age = 44
GROUP BY 
  pi.anchor_age;