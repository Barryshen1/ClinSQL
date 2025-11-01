WITH gi_bleeding_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 45
    AND diag.icd_code IN (
      'K920', 'K921', 'K922',  -- GI bleeding codes (ICD-10)
      'K250', 'K252', 'K254', 'K256',  -- gastric ulcer with bleeding
      'K260', 'K262', 'K264', 'K266',  -- duodenal ulcer with bleeding
      'K270', 'K272', 'K274', 'K276',  -- peptic ulcer with bleeding
      'K280', 'K282', 'K284', 'K286',  -- gastrojejunal ulcer with bleeding
      'K290', 'K291', 'K293', 'K294', 'K295', 'K296',  -- gastritis and duodenitis with bleeding
      'K570', 'K571', 'K572', 'K573', 'K574', 'K575',  -- diverticular disease with bleeding
      'K625'  -- rectal hemorrhage
    )
    AND diag.icd_version = 10
),
discharge_hemoglobin AS (
  SELECT le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN gi_bleeding_admissions gb
    ON le.hadm_id = gb.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON gb.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.itemid = 51222  -- Hemoglobin
    AND le.valuenum IS NOT NULL
    AND DATE(le.charttime) = DATE(adm.dischtime)
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS hgb_75th_percentile
FROM discharge_hemoglobin;