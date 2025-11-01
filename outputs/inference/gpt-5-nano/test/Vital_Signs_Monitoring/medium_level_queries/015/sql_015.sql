WITH sbp_per_stay AS (
  SELECT
    icu.stay_id,
    MAX(cev.valuenum) AS max_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS cev
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = cev.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = cev.subject_id
   AND icu.hadm_id = cev.hadm_id
   AND icu.stay_id = cev.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND adm.admission_type = 'EMERGENCY'
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%blood%'
    AND cev.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)
SELECT
  PERCENTILE_CONT(max_sbp, 0.75) OVER () AS p75_sbp
FROM sbp_per_stay
LIMIT 1;