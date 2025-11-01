WITH eligible_admissions AS (
  SELECT DISTINCT a.subject_id,
                  a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (LOWER(dd.long_title) LIKE '%chest pain%' OR LOWER(dd.long_title) LIKE '%myocardial infarction%')
),

troponin_events AS (
  SELECT le.subject_id,
         le.hadm_id,
         le.charttime,
         le.valuenum,
         le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND LOWER(le.valueuom) LIKE '%ng/mL%'
    AND le.valuenum > 0.01
),

first_times AS (
  SELECT t.subject_id,
         t.hadm_id,
         MIN(t.charttime) AS first_charttime
  FROM troponin_events AS t
  GROUP BY t.subject_id, t.hadm_id
),

first_troponin AS (
  SELECT ft.subject_id,
         ft.hadm_id,
         t.valuenum
  FROM first_times AS ft
  JOIN troponin_events AS t
    ON t.subject_id = ft.subject_id
   AND t.hadm_id = ft.hadm_id
   AND t.charttime = ft.first_charttime
)

SELECT
  AVG(ft.valuenum) AS mean_troponin_T_ng_per_mL,
  STDDEV_SAMP(ft.valuenum) AS stddev_troponin_T_ng_per_mL,
  MIN(ft.valuenum) AS min_troponin_T_ng_per_mL,
  MAX(ft.valuenum) AS max_troponin_T_ng_per_mL
FROM first_troponin AS ft
JOIN eligible_admissions AS ea
  ON ft.hadm_id = ea.hadm_id
 AND ft.subject_id = ea.subject_id;