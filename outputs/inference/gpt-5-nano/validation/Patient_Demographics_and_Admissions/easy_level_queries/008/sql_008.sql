WITH pci_events AS (
  SELECT p.subject_id,
         p.hadm_id,
         CAST(p.chartdate AS TIMESTAMP) AS charttime
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%percutaneous transluminal coronary angioplasty%' OR
    LOWER(d.long_title) LIKE '%coronary angioplasty%' OR
    LOWER(d.long_title) LIKE '%angioplasty%' OR
    LOWER(d.long_title) LIKE '%stent%' OR
    LOWER(d.long_title) LIKE '%pci%'
),
pci_first AS (
  SELECT subject_id,
         hadm_id,
         charttime
  FROM (
    SELECT subject_id,
           hadm_id,
           charttime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime) AS rn
    FROM pci_events
  ) t
  WHERE rn = 1
),
index_admissions AS (
  SELECT pf.subject_id,
         pf.hadm_id AS index_hadm_id,
         a.admittime AS index_admittime,
         a.dischtime AS index_dischtime
  FROM pci_first pf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pf.subject_id = a.subject_id AND pf.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
),
readmission AS (
  SELECT ia.subject_id,
         ia.index_hadm_id,
         ia.index_admittime,
         ia.index_dischtime,
         MAX(CASE WHEN ad.admittime IS NOT NULL THEN 1 ELSE 0 END) AS readmit_flag
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    ON ad.subject_id = ia.subject_id
   AND ad.admittime > ia.index_dischtime
   AND ad.admittime <= TIMESTAMP_ADD(ia.index_dischtime, INTERVAL 30 DAY)
  GROUP BY ia.subject_id, ia.index_hadm_id, ia.index_admittime, ia.index_dischtime
)
SELECT ROUND(AVG(readmit_flag) * 100, 2) AS thirty_day_readmission_rate_percent
FROM readmission;