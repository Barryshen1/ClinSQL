WITH troponin_t_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
),
troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    LOWER(COALESCE(le.valueuom, '')) AS valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_t_itemids it ON le.itemid = it.itemid
  WHERE le.valuenum IS NOT NULL
    AND LOWER(COALESCE(le.valueuom, '')) LIKE '%ng%'  -- limit to ng (e.g., ng/mL)
),
first_troponin_per_adm AS (
  -- take the earliest troponin event during the admission
  SELECT
    t.subject_id,
    t.hadm_id,
    t.charttime,
    t.valuenum AS first_troponin
  FROM (
    SELECT
      te.*,
      ROW_NUMBER() OVER (PARTITION BY te.subject_id, te.hadm_id ORDER BY te.charttime ASC) AS rn
    FROM troponin_events te
  ) t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON t.hadm_id = a.hadm_id
    AND t.subject_id = a.subject_id
    -- ensure the lab occurred during the admission
    AND t.charttime >= a.admittime
    AND t.charttime <= a.dischtime
  WHERE t.rn = 1
),
ihd_diagnoses AS (
  -- admissions with any diagnosis code for ischemic heart disease:
  -- ICD-9 prefixes 410-414, ICD-10 prefixes I20-I25
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
      d.icd_version = 9
      AND SUBSTR(d.icd_code, 1, 3) IN ('410','411','412','413','414')
    )
    OR (
      d.icd_version = 10
      AND UPPER(SUBSTR(d.icd_code, 1, 3)) IN ('I20','I21','I22','I23','I24','I25')
    )
),
eligible_admissions AS (
  -- link patients, admissions with IHD diagnoses and age/gender filters
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ihd_diagnoses id ON a.subject_id = id.subject_id AND a.hadm_id = id.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
)
SELECT
  cnt.n_admissions,
  q.q[OFFSET(25)] AS q1_troponin_ng_per_mL,
  q.q[OFFSET(50)] AS median_troponin_ng_per_mL,
  q.q[OFFSET(75)] AS q3_troponin_ng_per_mL,
  SAFE_CAST(q.q[OFFSET(75)] - q.q[OFFSET(25)] AS FLOAT64) AS iqr_troponin_ng_per_mL
FROM (
  SELECT APPROX_QUANTILES(ft.first_troponin, 100) AS q
  FROM first_troponin_per_adm ft
  JOIN eligible_admissions ea USING (subject_id, hadm_id)
  WHERE ft.first_troponin > 0.014  -- above the 99th percentile threshold given
) q
CROSS JOIN (
  SELECT COUNT(1) AS n_admissions
  FROM first_troponin_per_adm ft
  JOIN eligible_admissions ea USING (subject_id, hadm_id)
  WHERE ft.first_troponin > 0.014
) cnt;