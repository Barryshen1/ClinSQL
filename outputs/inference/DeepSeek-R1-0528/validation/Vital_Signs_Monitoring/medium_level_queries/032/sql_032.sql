WITH cohort AS (
  SELECT 
      a.hadm_id
  FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'F'
      AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 53 AND 63
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.transfers` t 
          WHERE 
              t.hadm_id = a.hadm_id 
              AND t.careunit IN ('Step Down', 'Intermediate Care')
      )
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
          WHERE 
              pe.hadm_id = a.hadm_id 
              AND pe.itemid = 227194  -- Invasive Ventilation
      )
)
SELECT 
    STDDEV(ce.valuenum) AS nighttime_sbp_stddev
FROM 
    cohort c
INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.hadm_id = ce.hadm_id
WHERE 
    ce.itemid IN (220179, 225309)  -- SBP measurements (Non-Invasive & Arterial)
    AND ce.valuenum IS NOT NULL
    AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5;  -- 00:00 to 05:59 (nighttime);