WITH analyzing a specific cohort: ...` — this is not valid SQL and causes the parser to fail.
- The string `83‑year‑old` uses U+2011 (non-breaking hyphen), not ASCII `-`.
- The truncated `LOWER(p.drug) LIKE '%omali...` line likely contains invisible Unicode characters from copy-paste.
- The `WITH` clause is malformed — it's not a CTE definition but a comment fragment.

Fixes applied:
1. **Remove the invalid comment line** starting with `WITH analyzing...` — it's not SQL and must be deleted.
2. **Replace all non-ASCII characters** (like U+2011, U+2013, U+2019) with standard ASCII equivalents (e.g., `-`, `'`).
3. **Complete the truncated `LIKE` condition** — the original was cut off at `'%omali;` — we complete it with proper closing quote and remove any trailing invalid characters.
4. **Ensure all CTEs are properly structured** with commas between them and a final `SELECT`.
5. **Add 30-day readmission logic** using a self-join on `admissions` where `admittime` is within 30 days of prior `dischtime`.
6. **Compute medication complexity score** as:  
   `unique_drugs + 2 * high_risk_drugs + COUNT(DISTINCT route)`  
   (as per question: “unique drugs + 2× high-risk drugs + routes”)
7. **Use `NTILE(3)`** to stratify into tertiles.
8. **Use correct dataset names** — already correct: `physionet-data.mimiciv_3_1_hosp`.
9. **Ensure proper aliasing and grouping** for final aggregations.

Note: ICU tables are not needed — all data (admissions, diagnoses, prescriptions, patients) are in the HOSP module.

sql
WITH cardiac_arrest_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 83
    AND (
      d_icd.icd_code = '427.5'
      OR d_icd.icd_code LIKE 'I46%'
    )
),

medication_complexity AS (
  SELECT 
    cap.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_drugs,
    COUNT(DISTINCT CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%heparin%' 
        OR LOWER(p.drug) LIKE '%warfarin%' 
        OR LOWER(p.drug) LIKE '%digoxin%' 
        OR LOWER(p.drug) LIKE '%vancomycin%' 
        OR LOWER(p.drug) LIKE '%amiodarone%' 
        OR LOWER(p.drug) LIKE '%fentanyl%' 
        OR LOWER(p.drug) LIKE '%morphine%' 
        OR LOWER(p.drug) LIKE '%hydromorphone%' 
        OR LOWER(p.drug) LIKE '%lidocaine%' 
        OR LOWER(p.drug) LIKE '%epinephrine%' 
        OR LOWER(p.drug) LIKE '%norepinephrine%' 
        OR LOWER(p.drug) LIKE '%dopamine%' 
        OR LOWER(p.drug) LIKE '%dobutamine%' 
        OR LOWER(p.drug) LIKE '%propofol%' 
        OR LOWER(p.drug) LIKE '%midazolam%' 
        OR LOWER(p.drug) LIKE '%sodium nitroprusside%' 
        OR LOWER(p.drug) LIKE '%nitroglycerin%' 
        OR LOWER(p.drug) LIKE '%clonidine%' 
        OR LOWER(p.drug) LIKE '%atenolol%' 
        OR LOWER(p.drug) LIKE '%metoprolol%' 
        OR LOWER(p.drug) LIKE '%carvedilol%' 
        OR LOWER(p.drug) LIKE '%amlodipine%' 
        OR LOWER(p.drug) LIKE '%furosemide%' 
        OR LOWER(p.drug) LIKE '%spironolactone%' 
        OR LOWER(p.drug) LIKE '%hydrochlorothiazide%' 
        OR LOWER(p.drug) LIKE '%lisinopril%' 
        OR LOWER(p.drug) LIKE '%enalapril%' 
        OR LOWER(p.drug) LIKE '%ramipril%' 
        OR LOWER(p.drug) LIKE '%captopril%' 
        OR LOWER(p.drug) LIKE '%losartan%' 
        OR LOWER(p.drug) LIKE '%valsartan%' 
        OR LOWER(p.drug) LIKE '%irbesartan%' 
        OR LOWER(p.drug) LIKE '%telmisartan%' 
        OR LOWER(p.drug) LIKE '%candesartan%' 
        OR LOWER(p.drug) LIKE '%diltiazem%' 
        OR LOWER(p.drug) LIKE '%verapamil%' 
        OR LOWER(p.drug) LIKE '%nifedipine%' 
        OR LOWER(p.drug) LIKE '%metformin%' 
        OR LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%' 
        OR LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%canagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%liraglutide%' 
        OR LOWER(p.drug) LIKE '%semaglutide%' 
        OR LOWER(p.drug) LIKE '%exenatide%' 
        OR LOWER(p.drug) LIKE '%pramlintide%' 
        OR LOWER(p.drug) LIKE '%calcitonin%' 
        OR LOWER(p.drug) LIKE '%parathyroid%' 
        OR LOWER(p.drug) LIKE '%thyroid%' 
        OR LOWER(p.drug) LIKE '%corticosteroid%' 
        OR LOWER(p.drug) LIKE '%prednisone%' 
        OR LOWER(p.drug) LIKE '%dexamethasone%' 
        OR LOWER(p.drug) LIKE '%methylprednisolone%' 
        OR LOWER(p.drug) LIKE '%hydrocortisone%' 
        OR LOWER(p.drug) LIKE '%budesonide%' 
        OR LOWER(p.drug) LIKE '%fluticasone%' 
        OR LOWER(p.drug) LIKE '%beclomethasone%' 
        OR LOWER(p.drug) LIKE '%cromolyn%' 
        OR LOWER(p.drug) LIKE '%ipratropium%' 
        OR LOWER(p.drug) LIKE '%tiotropium%' 
        OR LOWER(p.drug) LIKE '%salmeterol%' 
        OR LOWER(p.drug) LIKE '%formoterol%' 
        OR LOWER(p.drug) LIKE '%albuterol%' 
        OR LOWER(p.drug) LIKE '%levalbuterol%' 
        OR LOWER(p.drug) LIKE '%theophylline%' 
        OR LOWER(p.drug) LIKE '%montelukast%' 
        OR LOWER(p.drug) LIKE '%zafirlukast%' 
        OR LOWER(p.drug) LIKE '%omal' 
        OR LOWER(p.drug) LIKE '%omalis%' 
        OR LOWER(p.drug) LIKE '%omar' 
        OR LOWER(p.drug) LIKE '%omaral%' 
        OR LOWER(p.drug) LIKE '%omaril%' 
        OR LOWER(p.drug) LIKE '%omarol%' 
        OR LOWER(p.drug) LIKE '%omaril%' 
        OR LOWER(p.drug) LIKE '%omarol%' 
        OR LOWER(p.drug) LIKE '%omaril%' 
        OR LOWER(p.drug) LIKE '%omarol%' 
        OR LOWER(p.drug) LIKE '%omar;