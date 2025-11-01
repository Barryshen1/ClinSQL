WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
    AND d1.icd_code LIKE 'E11%'
    AND d1.icd_version = 10
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
    AND d2.icd_code LIKE 'I50%'
    AND d2.icd_version = 10
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),

first24 AS (
  SELECT
    p.hadm_id,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%insulin%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%'
        OR LOWER(p.drug) LIKE '%empagliflozin%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        OR LOWER(p.drug) LIKE '%nateglinide%'
        OR LOWER(p.drug) LIKE '%vildagliptin%'
        OR LOWER(p.drug) LIKE '%alogliptin%'
        OR LOWER(p.drug) LIKE '%linagliptin%'
        OR LOWER(p.drug) LIKE '%saxagliptin%'
        OR LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%pramlintide%'
        OR LOWER(p.drug) LIKE '%tirzepatide%'
      THEN 1 ELSE 0 END) AS antidiabetic,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%metoprolol%'
        OR LOWER(p.drug) LIKE '%atenolol%'
        OR LOWER(p.drug) LIKE '%carvedilol%'
        OR LOWER(p.drug) LIKE '%propranolol%'
        OR LOWER(p.drug) LIKE '%bisoprolol%'
        OR LOWER(p.drug) LIKE '%nadolol%'
        OR LOWER(p.drug) LIKE '%labetalol%'
        OR LOWER(p.drug) LIKE '%timolol%'
        OR LOWER(p.drug) LIKE '%esmolol%'
        OR LOWER(p.drug) LIKE '%nebivolol%'
      THEN 1 ELSE 0 END) AS beta_blocker,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%lisinopril%'
        OR LOWER(p.drug) LIKE '%enalapril%'
        OR LOWER(p.drug) LIKE '%ramipril%'
        OR LOWER(p.drug) LIKE '%captopril%'
        OR LOWER(p.drug) LIKE '%quinapril%'
        OR LOWER(p.drug) LIKE '%benazepril%'
        OR LOWER(p.drug) LIKE '%perindopril%'
        OR LOWER(p.drug) LIKE '%trandolapril%'
        OR LOWER(p.drug) LIKE '%moexipril%'
        OR LOWER(p.drug) LIKE '%fosinopril%'
        OR LOWER(p.drug) LIKE '%losartan%'
        OR LOWER(p.drug) LIKE '%valsartan%'
        OR LOWER(p.drug) LIKE '%irbesartan%'
        OR LOWER(p.drug) LIKE '%candesartan%'
        OR LOWER(p.drug) LIKE '%telmisartan%'
        OR LOWER(p.drug) LIKE '%olmesartan%'
        OR LOWER(p.drug) LIKE '%azilsartan%'
        OR LOWER(p.drug) LIKE '%eprosartan%'
        OR LOWER(p.drug) LIKE '%sacubitril/valsartan%'
        OR LOWER(p.drug) LIKE '%entresto%'
      THEN 1 ELSE 0 END) AS ace_arb_arni,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%furosemide%'
        OR LOWER(p.drug) LIKE '%bumetanide%'
        OR LOWER(p.drug) LIKE '%torsemide%'
      THEN 1 ELSE 0 END) AS loop_diuretic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_admissions ea
    ON p.hadm_id = ea.hadm_id
  WHERE
    p.starttime < ea.admittime + INTERVAL '24' HOUR
    AND p.stoptime > ea.admittime
  GROUP BY p.hadm_id
),

final48 AS (
  SELECT
    p.hadm_id,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%insulin%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%'
        OR LOWER(p.drug) LIKE '%empagliflozin%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        OR LOWER(p.drug) LIKE '%nateglinide%'
        OR LOWER(p.drug) LIKE '%vildagliptin%'
        OR LOWER(p.drug) LIKE '%alogliptin%'
        OR LOWER(p.drug) LIKE '%linagliptin%'
        OR LOWER(p.drug) LIKE '%saxagliptin%'
        OR LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%pramlintide%'
        OR LOWER(p.drug) LIKE '%tirzepatide%'
      THEN 1 ELSE 0 END) AS antidiabetic,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%metoprolol%'
        OR LOWER(p.drug) LIKE '%atenolol%'
        OR LOWER(p.drug) LIKE '%carvedilol%'
        OR LOWER(p.drug) LIKE '%propranolol%'
        OR LOWER(p.drug) LIKE '%bisoprolol%'
        OR LOWER(p.drug) LIKE '%nadolol%'
        OR LOWER(p.drug) LIKE '%labetalol%'
        OR LOWER(p.drug) LIKE '%timolol%'
        OR LOWER(p.drug) LIKE '%esmolol%'
        OR LOWER(p.drug) LIKE '%nebivolol%'
      THEN 1 ELSE 0 END) AS beta_blocker,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%lisinopril%'
        OR LOWER(p.drug) LIKE '%enalapril%'
        OR LOWER(p.drug) LIKE '%ramipril%'
        OR LOWER(p.drug) LIKE '%captopril%'
        OR LOWER(p.drug) LIKE '%quinapril%'
        OR LOWER(p.drug) LIKE '%benazepril%'
        OR LOWER(p.drug) LIKE '%perindopril%'
        OR LOWER(p.drug) LIKE '%trandolapril%'
        OR LOWER(p.drug) LIKE '%moexipril%'
        OR LOWER(p.drug) LIKE '%fosinopril%'
        OR LOWER(p.drug) LIKE '%losartan%'
        OR LOWER(p.drug) LIKE '%valsartan%'
        OR LOWER(p.drug) LIKE '%irbesartan%'
        OR LOWER(p.drug) LIKE '%candesartan%'
        OR LOWER(p.drug) LIKE '%telmisartan%'
        OR LOWER(p.drug) LIKE '%olmesartan%'
        OR LOWER(p.drug) LIKE '%azilsartan%'
        OR LOWER(p.drug) LIKE '%eprosartan%'
        OR LOWER(p.drug) LIKE '%sacubitril/valsartan%'
        OR LOWER(p.drug) LIKE '%entresto%'
      THEN 1 ELSE 0 END) AS ace_arb_arni,
    MAX(CASE
      WHEN LOWER(p.drug) LIKE '%furosemide%'
        OR LOWER(p.drug) LIKE '%bumetanide%'
        OR LOWER(p.drug) LIKE '%torsemide%'
      THEN 1 ELSE 0 END) AS loop_diuretic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_admissions ea
    ON p.hadm_id = ea.hadm_id
  WHERE
    p.starttime < ea.dischtime
    AND p.stoptime > ea.dischtime - INTERVAL '48' HOUR
  GROUP BY p.hadm_id
)

SELECT
  COUNT(*) AS total_admissions,
  AVG(COALESCE(f.antidiabetic, 0)) * 100 AS antidiabetic_first24_percent,
  AVG(COALESCE(ff.antidiabetic, 0)) * 100 AS antidiabetic_final48_percent,
  SUM(CASE WHEN f.antidiabetic = 1 AND ff.antidiabetic = 1 THEN 1 ELSE 0 END) AS antidiabetic_continued,
  SUM(CASE WHEN f.antidiabetic = 0 AND ff.antidiabetic = 1 THEN 1 ELSE 0 END) AS antidiabetic_initiated,
  SUM(CASE WHEN f.antidiabetic = 1 AND ff.antidiabetic = 0 THEN 1 ELSE 0 END) AS antidiabetic_discontinued,
  AVG(COALESCE(f.beta_blocker, 0)) * 100 AS beta_blocker_first24_percent,
  AVG(COALESCE(ff.beta_blocker, 0)) * 100 AS beta_blocker_final48_percent,
  SUM(CASE WHEN f.beta_blocker = 1 AND ff.beta_blocker = 1 THEN 1 ELSE 0 END) AS beta_blocker_continued,
  SUM(CASE WHEN f.beta_blocker = 0 AND ff.beta_blocker = 1 THEN 1 ELSE 0 END) AS beta_blocker_initiated,
  SUM(CASE WHEN f.beta_blocker = 1 AND ff.beta_blocker = 0 THEN 1 ELSE 0 END) AS beta_blocker_discontinued,
  AVG(COALESCE(f.ace_arb_arni, 0)) * 100 AS ace_arb_arni_first24_percent,
  AVG(COALESCE(ff.ace_arb_arni, 0)) * 100 AS ace_arb_arni_final48_percent,
  SUM(CASE WHEN f.ace_arb_arni = 1 AND ff.ace_arb_arni = 1 THEN 1 ELSE 0 END) AS ace_arb_arni_continued,
  SUM(CASE WHEN f.ace_arb_arni = 0 AND ff.ace_arb_arni = 1 THEN 1 ELSE 0 END) AS ace_arb_arni_initiated,
  SUM(CASE WHEN f.ace_arb_arni = 1 AND ff.ace_arb_arni = 0 THEN 1 ELSE 0 END) AS ace_arb_arni_discontinued,
  AVG(COALESCE(f.loop_diuretic, 0)) * 100 AS loop_diuretic_first24_percent,
  AVG(COALESCE(ff.loop_diuretic, 0)) * 100 AS loop_diuretic_final48_percent,
  SUM(CASE WHEN f.loop_diuretic = 1 AND ff.loop_diuretic = 1 THEN 1 ELSE 0 END) AS loop_diuretic_continued,
  SUM(CASE WHEN f.loop_diuretic = 0 AND ff.loop_diuretic = 1 THEN 1 ELSE 0 END) AS loop_diuretic_initiated,
  SUM(CASE WHEN f.loop_diuretic = 1 AND ff.loop_diuretic = 0 THEN 1 ELSE 0 END) AS loop_diuretic_discontinued
FROM eligible_admissions ea
LEFT JOIN first24 f ON ea.hadm_id = f.hadm_id
LEFT JOIN final48 ff ON ea.hadm_id = ff.hadm_id;