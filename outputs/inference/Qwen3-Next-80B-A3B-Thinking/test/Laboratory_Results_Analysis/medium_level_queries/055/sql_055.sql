WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
),
diagnoses_for_cxpain_ami AS (
  SELECT
    fa.hadm_id,
    fa.los
  FROM filtered_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    d.seq_num = 1
    AND (dicd.long_title LIKE '%acute myocardial infarction%'
         OR dicd.long_title LIKE '%chest pain%')
),
hs_tnt_tests AS (
  SELECT
    d.hadm_id,
    le.valuenum,
    CASE
      WHEN le.valuenum < 14 THEN 'normal'
      WHEN le.valuenum BETWEEN 14 AND 50 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM diagnoses_for_cxpain_ami d
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON d.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE
    (di.label LIKE '%hs-TnT%' OR di.label LIKE '%high sensitivity troponin%')
    AND le.valueuom = 'ng/L'
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY d.hadm_id ORDER BY le.charttime) = 1
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(d.los) AS mean_los
FROM hs_tnt_tests h
JOIN diagnoses_for_cxpain_ami d
  ON h.hadm_id = d.hadm_id
GROUP BY category;