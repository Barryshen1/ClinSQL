WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high-sensitivity%')
),
early_tn AS (
  SELECT le.subject_id,
         le.hadm_id,
         le.charttime,
         le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti ON le.itemid = ti.itemid
),
first_tn AS (
  SELECT subject_id, hadm_id, charttime, valuenum,
         ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id
                            ORDER BY charttime ASC, valuenum DESC) AS rn
  FROM early_tn
),
first_tn_per_adm AS (
  SELECT subject_id, hadm_id, charttime, valuenum
  FROM first_tn
  WHERE rn = 1
),
acs_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
          di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR
          di.icd_code LIKE '412%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%'
        )
),
joined AS (
  SELECT ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime, tn.valuenum
  FROM acs_cohort ac
  JOIN first_tn_per_adm tn
    ON ac.subject_id = tn.subject_id AND ac.hadm_id = tn.hadm_id
),
tot AS (
  SELECT COUNT(*) AS total FROM joined
)
SELECT
  CASE
    WHEN j.valuenum < 14 THEN 'Normal'
    WHEN j.valuenum >= 14 AND j.valuenum <= 53 THEN 'Borderline'
    WHEN j.valuenum > 53 THEN 'Myocardial Injury'
    ELSE 'Unknown'
  END AS hs_tnT_category,
  COUNT(*) AS count_in_category,
  SAFE_DIVIDE(COUNT(*), t.total) * 100.0 AS percentage_of_total,
  AVG(TIMESTAMP_DIFF(j.dischtime, j.admittime, SECOND) / 86400.0) AS mean_hospital_los_days
FROM joined j
CROSS JOIN tot t
GROUP BY hs_tnT_category, t.total
ORDER BY hs_tnT_category;