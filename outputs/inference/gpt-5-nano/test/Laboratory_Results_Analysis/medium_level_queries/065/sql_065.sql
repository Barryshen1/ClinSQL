WITH AMI_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND di.icd_version = 9
    AND di.icd_code LIKE '410%'
),

first_troponin AS (
  SELECT le.hadm_id,
         le.charttime,
         le.valuenum,
         LOWER(le.valueuom) AS valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM AMI_admissions)
    AND LOWER(dli.label) LIKE '%troponin%t%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),

eligible AS (
  SELECT hadm_id, valuenum
  FROM first_troponin
  WHERE valuenum > 0.04
    AND valueuom LIKE '%ng/mL%'
)

SELECT
  quantiles[OFFSET(1)] AS q1_initial_troponin_T_ng_per_mL,
  quantiles[OFFSET(2)] AS median_initial_troponin_T_ng_per_mL,
  quantiles[OFFSET(3)] AS q3_initial_troponin_T_ng_per_mL
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM eligible
) t;