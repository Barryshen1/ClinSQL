WITH qualifying_stays AS (
  SELECT 
    ie.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE 
        ce.stay_id = ie.stay_id
        AND (
          (ce.itemid = 227287 AND ce.valuenum > 0)  -- Flow rate >0
          OR (ce.itemid = 223834 AND ce.value = 'High Flow Nasal Cannula')  -- Exact device name
        )
    )
),
stay_sbp AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.stay_id IN (SELECT stay_id FROM qualifying_stays)
    AND ce.itemid IN (220050, 220179)  -- Systolic BP itemids
    AND ce.valuenum > 0  -- Valid measurements only
  GROUP BY 
    ce.stay_id
)
SELECT 
  MIN(mean_sbp) AS min_mean_sbp
FROM 
  stay_sbp;