WITH qualifying_hadms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t 
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (t.careunit LIKE '%Stepdown%' OR t.careunit LIKE '%IMC%')
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce_vent
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i_vent 
        ON ce_vent.stay_id = i_vent.stay_id
      WHERE i_vent.subject_id = a.subject_id
        AND i_vent.hadm_id = a.hadm_id
        AND ce_vent.itemid IN (720, 721, 722, 723, 724, 725, 726, 727, 223848, 223849)
        AND ce_vent.valuenum IS NOT NULL
    )
)
SELECT STDDEV(ce.valuenum) AS nighttime_sbp_stddev_mmhg
FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
  ON ce.stay_id = i.stay_id
INNER JOIN qualifying_hadms qh 
  ON i.hadm_id = qh.hadm_id
WHERE ce.itemid IN (220045, 220179)
  AND ce.valueuom = 'mmHg'
  AND ce.valuenum IS NOT NULL
  AND EXTRACT(HOUR FROM ce.charttime) >= 0 
  AND EXTRACT(HOUR FROM ce.charttime) < 6;