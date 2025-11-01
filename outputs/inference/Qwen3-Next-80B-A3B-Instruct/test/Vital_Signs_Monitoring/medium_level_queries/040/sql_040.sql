WITH hfnc_stays AS (
  SELECT DISTINCT i.stay_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(di.label) LIKE '%high flow%' 
    AND LOWER(di.label) LIKE '%nasal cannula%'
    AND ce.value IS NOT NULL
),
sbp_means AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(di.label) IN ('arterial bp systolic', 'bp systolic', 'sbp', 'systolic blood pressure')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 250  -- reasonable physiological range
    AND i.stay_id IN (SELECT stay_id FROM hfnc_stays)  -- only stays with HFNC
  GROUP BY i.stay_id
)
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM sbp_means;