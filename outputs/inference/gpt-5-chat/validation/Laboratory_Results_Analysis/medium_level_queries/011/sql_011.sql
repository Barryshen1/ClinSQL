WITH chest_pain_adm AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code
   AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 61 AND 71
    AND LOWER(dxd.long_title) LIKE '%chest pain%'
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum, le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND LOWER(di.label) LIKE '%high%'
    AND le.valuenum IS NOT NULL
)
, first_tnt AS (
  SELECT cpa.subject_id, cpa.hadm_id,
         t.charttime, t.valuenum, t.valueuom,
         ROW_NUMBER() OVER (PARTITION BY cpa.subject_id, cpa.hadm_id ORDER BY t.charttime ASC) AS rn
  FROM chest_pain_adm cpa
  JOIN troponin_labs t
    ON cpa.subject_id = t.subject_id
   AND cpa.hadm_id = t.hadm_id
)
, categorized AS (
  SELECT subject_id, hadm_id,
         valuenum,
         CASE
           WHEN valuenum < 14 THEN 'Normal'
           WHEN valuenum BETWEEN 14 AND 50 THEN 'Borderline'
           WHEN valuenum > 50 THEN 'Myocardial injury'
           ELSE 'Unknown'
         END AS category
  FROM first_tnt
  WHERE rn = 1
)
SELECT category,
       COUNT(*) AS n,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_distribution
FROM categorized
GROUP BY category
ORDER BY category;