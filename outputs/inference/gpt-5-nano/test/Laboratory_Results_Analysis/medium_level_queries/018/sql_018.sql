WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%')  -- ACS proxy
    AND UPPER(p.gender) = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100
),
troponin_index AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    MIN(l.charttime) AS index_charttime
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = b.subject_id AND l.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%troponin t%') OR (LOWER(di.label) LIKE '%troponin-t%')
  GROUP BY b.subject_id, b.hadm_id
),
troponin_class AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    b.LOS_days,
    l.valuenum AS troponin_value,
    CASE
      WHEN l.valuenum <= 0.01 THEN 'Normal'
      WHEN l.valuenum <= 0.04 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM troponin_index t
  JOIN base b
    ON b.subject_id = t.subject_id AND b.hadm_id = t.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = t.subject_id AND l.hadm_id = t.hadm_id AND l.charttime = t.index_charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE (LOWER(di.label) LIKE '%troponin t%') OR (LOWER(di.label) LIKE '%troponin-t%')
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN troponin_category = 'Normal' THEN 1 ELSE 0 END) AS normal_count,
  SUM(CASE WHEN troponin_category = 'Borderline' THEN 1 ELSE 0 END) AS borderline_count,
  SUM(CASE WHEN troponin_category = 'Elevated' THEN 1 ELSE 0 END) AS elevated_count,
  SAFE_DIVIDE(SUM(CASE WHEN troponin_category = 'Normal' THEN 1 ELSE 0 END), COUNT(*)) AS normal_pct,
  SAFE_DIVIDE(SUM(CASE WHEN troponin_category = 'Borderline' THEN 1 ELSE 0 END), COUNT(*)) AS borderline_pct,
  SAFE_DIVIDE(SUM(CASE WHEN troponin_category = 'Elevated' THEN 1 ELSE 0 END), COUNT(*)) AS elevated_pct,
  AVG(LOS_days) AS mean_los_days
FROM troponin_class;